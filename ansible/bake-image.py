#!/usr/bin/env python3
import os
import sys
import json
import subprocess
import tempfile
import shutil
from pathlib import Path
from string import Template

# Configuration parameters (can be overridden via environment variables)
IMG = Path("ansible/raspios-lite-arm64.img")
XZ_URL = "https://downloads.raspberrypi.org/raspios_lite_arm64_latest"
STATIC_IP = os.getenv("PI_STATIC_IP", "192.168.1.105/24")
GATEWAY = os.getenv("PI_GATEWAY", "192.168.1.1")
DNS_SERVERS = os.getenv("PI_DNS", "[1.1.1.1, 8.8.8.8]")
USERNAME = os.getenv("PI_USER", "skoltun")
HOSTNAME = os.getenv("PI_HOSTNAME", "raspberry-pi")
TIMEZONE = os.getenv("PI_TIMEZONE", "Europe/Warsaw")
TEMPLATE_DIR = Path("ansible/cloud-init")

def run_cmd(cmd, sudo=False):
    if sudo and os.geteuid() != 0:
        cmd = ["sudo"] + cmd
    print(f"-> Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

def fetch_ssh_key():
    print("Checking Bitwarden CLI status...")
    if not shutil.which("bw"):
        print("Error: Bitwarden CLI (bw) not found. Run 'mise install' first.")
        sys.exit(1)

    bw_session = os.environ.get("BW_SESSION")
    if not bw_session:
        print("Bitwarden vault is locked. Please unlock it:")
        # stdout is captured to grab the session key, but stderr is left uncaptured
        # so the "Master password:" prompt is visible in your terminal.
        res = subprocess.run(
            ["bw", "unlock", "--raw"],
            stdout=subprocess.PIPE,
            text=True,
            check=True
        )
        os.environ["BW_SESSION"] = res.stdout.strip()

    print("Fetching SSH public key from Bitwarden...")
    item_res = subprocess.run(
        ["bw", "get", "item", "homelab-ssh-key"],
        capture_output=True, text=True, check=True, env=os.environ
    )
    item_data = json.loads(item_res.stdout)
    pub_key = item_data.get("sshKey", {}).get("publicKey")

    if not pub_key or pub_key == "null":
        print("Error: Could not retrieve SSH public key from Bitwarden.")
        sys.exit(1)
    return pub_key.strip()

def main():
    # 1. Download and extract image if missing
    if not IMG.exists():
        img_xz = IMG.with_suffix(".img.xz")
        print(f"Downloading latest Raspberry Pi OS Lite from official source...")
        run_cmd(["curl", "-L", "-o", str(img_xz), XZ_URL])
        print("Decompressing image...")
        run_cmd(["xz", "-d", str(img_xz)])

    # 2. Fetch Bitwarden SSH Key
    pub_key = fetch_ssh_key()

    # 3. Render Templates
    temp_dir = Path(tempfile.mkdtemp())
    try:
        print("Rendering cloud-init configurations...")
        context = {
            "username": USERNAME,
            "pub_key": pub_key,
            "timezone": TIMEZONE,
            "static_ip": STATIC_IP,
            "gateway": GATEWAY,
            "dns_servers": DNS_SERVERS,
            "instance_id": f"{HOSTNAME}-instance",
            "hostname": HOSTNAME
        }

        for filename in ["user-data", "meta-data", "network-config"]:
            template_path = TEMPLATE_DIR / f"{filename}.template"
            content = template_path.read_text()
            rendered = Template(content).substitute(context)
            (temp_dir / filename).write_text(rendered)

        # 4. Loop-mount image partitions
        print("Loop-mounting raw image partitions...")
        res = subprocess.run(
            ["sudo", "losetup", "--find", "--show", "-P", str(IMG)],
            capture_output=True, text=True, check=True
        )
        loop_dev = res.stdout.strip()

        mnt_dir = temp_dir / "mnt"
        mnt_dir.mkdir()

        try:
            run_cmd(["mount", f"{loop_dev}p1", str(mnt_dir)], sudo=True)

            # 5. Patch kernel cgroups
            cmdline_path = mnt_dir / "cmdline.txt"
            cmdline_content = cmdline_path.read_text()
            if "cgroup_memory=1" not in cmdline_content:
                print("Enabling memory cgroups in kernel boot parameters...")
                new_content = cmdline_content.strip() + " cgroup_memory=1 cgroup_enable=memory\n"
                subprocess.run(
                    f"echo '{new_content.strip()}' | sudo tee {cmdline_path}",
                    shell=True, check=True
                )

            # 6. Copy files to boot partition & enable SSH server
            print("Injecting configuration files and enabling SSH into boot partition...")
            for filename in ["user-data", "meta-data", "network-config"]:
                run_cmd(["cp", str(temp_dir / filename), str(mnt_dir / filename)], sudo=True)

            # Raspberry Pi OS requires an empty 'ssh' file in the boot partition to open port 22
            run_cmd(["touch", str(mnt_dir / "ssh")], sudo=True)

        finally:
            # Cleanup mount and loop device safely
            subprocess.run(["sudo", "umount", str(mnt_dir)], capture_output=True)
            subprocess.run(["sudo", "losetup", "-d", loop_dev], capture_output=True)

        print(f"\nSuccess! Prebaked image ready at: {IMG}")
        print(f"Configured Static IP: {STATIC_IP}")
        print("Flash it to your SD card using Rufus, Balena Etcher, or Raspberry Pi Imager.")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

if __name__ == "__main__":
    main()