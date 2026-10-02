#!/usr/bin/env python3
import os
import sys
import json
import subprocess
import tempfile
import shutil
import tomllib
from pathlib import Path
from string import Template

BASE_DIR = Path(__file__).resolve().parent
CONFIG_FILE = BASE_DIR / "config.toml"
TEMPLATE_DIR = BASE_DIR / "templates"
XZ_URL = "https://downloads.raspberrypi.org/raspios_lite_arm64_latest"

def load_config():
    """Load configuration from TOML file with environment variable fallback overrides."""
    if not CONFIG_FILE.exists():
        print(f"Error: Configuration file not found at {CONFIG_FILE}")
        sys.exit(1)

    with open(CONFIG_FILE, "rb") as f:
        config = tomllib.load(f)

    pi = config.get("pi", {})
    net = config.get("network", {})

    # If image path is relative, make it resolve from the repo root (2 levels up from scripts/raspberry)
    repo_root = BASE_DIR.parent.parent
    img_path_raw = pi.get("image_path", "ansible/raspios-lite-arm64.img")
    img_path = repo_root / img_path_raw if not Path(img_path_raw).is_absolute() else Path(img_path_raw)

    # Format DNS servers list back to string format for cloud-init template if needed
    dns_list = net.get("dns_servers", ["1.1.1.1", "8.8.8.8"])
    dns_str = "[" + ", ".join(dns_list) + "]"

    return {
        "img": img_path,
        "username": os.getenv("PI_USER", pi.get("username", "skoltun")),
        "hostname": os.getenv("PI_HOSTNAME", pi.get("hostname", "raspberry-pi")),
        "timezone": os.getenv("PI_TIMEZONE", pi.get("timezone", "Europe/Warsaw")),
        "static_ip": os.getenv("PI_STATIC_IP", net.get("static_ip", "192.168.1.105/24")),
        "gateway": os.getenv("PI_GATEWAY", net.get("gateway", "192.168.1.1")),
        "dns_servers": os.getenv("PI_DNS", dns_str),
    }

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
    cfg = load_config()

    # 1. Download and extract image if missing
    if not cfg["img"].exists():
        # Ensure parent directory for the image exists
        cfg["img"].parent.mkdir(parents=True, exist_ok=True)
        img_xz = cfg["img"].with_suffix(".img.xz")
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
            "username": cfg["username"],
            "pub_key": pub_key,
            "timezone": cfg["timezone"],
            "static_ip": cfg["static_ip"],
            "gateway": cfg["gateway"],
            "dns_servers": cfg["dns_servers"],
            "instance_id": f"{cfg['hostname']}-instance",
            "hostname": cfg["hostname"]
        }

        for filename in ["user-data", "meta-data", "network-config"]:
            template_path = TEMPLATE_DIR / f"{filename}.template"
            content = template_path.read_text()
            rendered = Template(content).substitute(context)
            (temp_dir / filename).write_text(rendered)

        # 4. Loop-mount image partitions
        print("Loop-mounting raw image partitions...")
        res = subprocess.run(
            ["sudo", "losetup", "--find", "--show", "-P", str(cfg["img"])],
            capture_output=True, text=True, check=True
        )
        loop_dev = res.stdout.strip()

        mnt_dir = temp_dir / "mnt"
        mnt_dir.mkdir()

        root_mnt = temp_dir / "root_mnt"
        root_mnt.mkdir()

        try:
            # Mount boot partition (p1)
            run_cmd(["mount", f"{loop_dev}p1", str(mnt_dir)], sudo=True)

            # Patch kernel cgroups
            cmdline_path = mnt_dir / "cmdline.txt"
            cmdline_content = cmdline_path.read_text()
            if "cgroup_memory=1" not in cmdline_content:
                print("Enabling memory cgroups in kernel boot parameters...")
                new_content = cmdline_content.strip() + " cgroup_memory=1 cgroup_enable=memory\n"
                subprocess.run(
                    f"echo '{new_content.strip()}' | sudo tee {cmdline_path}",
                    shell=True, check=True
                )

            # Copy cloud-init files & enable SSH
            print("Injecting configuration files and enabling SSH into boot partition...")
            for filename in ["user-data", "meta-data", "network-config"]:
                run_cmd(["cp", str(temp_dir / filename), str(mnt_dir / filename)], sudo=True)
            run_cmd(["touch", str(mnt_dir / "ssh")], sudo=True)

            # Mount root partition (p2) to customize system files
            run_cmd(["mount", f"{loop_dev}p2", str(root_mnt)], sudo=True)

            print("Customizing system files on root partition...")
            wifi_check_path = root_mnt / "etc" / "profile.d" / "wifi-check.sh"
            if wifi_check_path.exists():
                run_cmd(["rm", "-f", str(wifi_check_path)], sudo=True)

            motd_path = root_mnt / "etc" / "motd"
            custom_motd = (
                "===================================================\n"
                f" 🚀 Raspberry Pi Homelab Node [{cfg['hostname']}] -- Zero-Touch\n"
                "===================================================\n"
            )
            subprocess.run(
                f"sudo tee {motd_path} > /dev/null",
                input=custom_motd, text=True, shell=True, check=True
            )

        finally:
            # Cleanup mounts and loop device safely
            subprocess.run(["sudo", "umount", str(mnt_dir)], capture_output=True)
            subprocess.run(["sudo", "umount", str(root_mnt)], capture_output=True)
            subprocess.run(["sudo", "losetup", "-d", loop_dev], capture_output=True)

        print(f"\nSuccess! Prebaked image ready at: {cfg['img']}")
        print(f"Configured Static IP: {cfg['static_ip']}")
        print("Flash it to your SD card using Rufus, Balena Etcher, or Raspberry Pi Imager.")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

if __name__ == "__main__":
    main()