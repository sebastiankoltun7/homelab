#!/usr/bin/env python3
import os
import sys
import subprocess
import tempfile
import shutil
import tomllib
from pathlib import Path
from string import Template
from contextlib import contextmanager
from typing import Dict, Any, Generator, Tuple
from bitwarden.bitwarden_get import get_bitwarden_field

BASE_DIR = Path(__file__).resolve().parent
CONFIG_FILE = BASE_DIR / "config.toml"
TEMPLATE_DIR = BASE_DIR / "templates"
XZ_URL = "https://downloads.raspberrypi.org/raspios_lite_arm64_latest"

def load_config() -> Dict[str, Any]:
    """Load configuration from TOML file with environment variable fallback overrides."""
    if not CONFIG_FILE.exists():
        print(f"Error: Configuration file not found at {CONFIG_FILE}", file=sys.stderr)
        sys.exit(1)

    with open(CONFIG_FILE, "rb") as f:
        config = tomllib.load(f)

    pi = config.get("pi", {})
    net = config.get("network", {})

    repo_root = BASE_DIR.parent.parent
    img_path_raw = pi.get("image_path", "ansible/raspios-lite-arm64.img")
    img_path = repo_root / img_path_raw if not Path(img_path_raw).is_absolute() else Path(img_path_raw)

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

def run_cmd(cmd: list[str], sudo: bool = False) -> None:
    """Run a shell command with optional sudo escalation."""
    if sudo and os.geteuid() != 0:
        cmd = ["sudo"] + cmd
    print(f"-> Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

def ensure_image_exists(img_path: Path) -> None:
    """Download and decompress Raspberry Pi OS Lite if it doesn't exist locally."""
    if img_path.exists():
        return

    img_path.parent.mkdir(parents=True, exist_ok=True)
    img_xz = img_path.with_suffix(".img.xz")
    print("Downloading latest Raspberry Pi OS Lite from official source...")
    run_cmd(["curl", "-L", "-o", str(img_xz), XZ_URL])
    print("Decompressing image...")
    run_cmd(["xz", "-d", str(img_xz)])

def fetch_ssh_key() -> str:
    """Fetch SSH public key securely from Bitwarden."""
    print("Fetching SSH public key from Bitwarden...")
    try:
        pub_key = get_bitwarden_field("homelab-ssh-key", ".sshKey.publicKey")
        if not pub_key:
            raise ValueError("Retrieved SSH public key is empty.")
        return pub_key.strip()
    except Exception as e:
        print(f"Error fetching SSH key: {e}", file=sys.stderr)
        sys.exit(1)

def render_templates(temp_dir: Path, cfg: Dict[str, Any], pub_key: str) -> None:
    """Render cloud-init template files with configuration context."""
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

@contextmanager
def mount_image_partitions(img_path: Path) -> Generator[Tuple[str, Path, Path], None, None]:
    """Context manager to safely loop-mount image partitions and clean them up automatically."""
    res = subprocess.run(
        ["sudo", "losetup", "--find", "--show", "-P", str(img_path)],
        capture_output=True, text=True, check=True
    )
    loop_dev = res.stdout.strip()

    temp_dir = Path(tempfile.mkdtemp())
    mnt_dir = temp_dir / "mnt"
    root_mnt = temp_dir / "root_mnt"
    mnt_dir.mkdir()
    root_mnt.mkdir()

    try:
        run_cmd(["mount", f"{loop_dev}p1", str(mnt_dir)], sudo=True)
        run_cmd(["mount", f"{loop_dev}p2", str(root_mnt)], sudo=True)
        yield loop_dev, mnt_dir, root_mnt
    finally:
        subprocess.run(["sudo", "umount", str(mnt_dir)], capture_output=True)
        subprocess.run(["sudo", "umount", str(root_mnt)], capture_output=True)
        subprocess.run(["sudo", "losetup", "-d", loop_dev], capture_output=True)
        shutil.rmtree(temp_dir, ignore_errors=True)

def customize_image(mnt_dir: Path, root_mnt: Path, temp_dir: Path, hostname: str) -> None:
    """Inject configuration files, enable cgroups, and customize system files."""

    # 1. Enable memory cgroups in kernel boot parameters
    cmdline_path = mnt_dir / "cmdline.txt"
    cmdline_content = cmdline_path.read_text()
    if "cgroup_memory=1" not in cmdline_content:
        print("Enabling memory cgroups in kernel boot parameters...")
        new_content = cmdline_content.strip() + " cgroup_memory=1 cgroup_enable=memory\n"
        subprocess.run(
            f"echo '{new_content.strip()}' | sudo tee {cmdline_path}",
            shell=True, check=True
        )

    # 2. Inject cloud-init configs and SSH marker
    print("Injecting configuration files and enabling SSH into boot partition...")
    for filename in ["user-data", "meta-data", "network-config"]:
        run_cmd(["cp", str(temp_dir / filename), str(mnt_dir / filename)], sudo=True)
    run_cmd(["touch", str(mnt_dir / "ssh")], sudo=True)

    # 3. Clean up default setup scripts and set custom MOTD
    print("Customizing system files on root partition...")
    wifi_check_path = root_mnt / "etc" / "profile.d" / "wifi-check.sh"
    if wifi_check_path.exists():
        run_cmd(["rm", "-f", str(wifi_check_path)], sudo=True)

    motd_path = root_mnt / "etc" / "motd"
    custom_motd = (
        "==================================================-\n"
        f" 🚀 Raspberry Pi Homelab Node [{hostname}] -- Zero-Touch\n"
        "==================================================-\n"
    )
    subprocess.run(
        f"sudo tee {motd_path} > /dev/null",
        input=custom_motd, text=True, shell=True, check=True
    )

def main() -> None:
    cfg = load_config()
    ensure_image_exists(cfg["img"])
    pub_key = fetch_ssh_key()

    temp_dir = Path(tempfile.mkdtemp())
    try:
        render_templates(temp_dir, cfg, pub_key)

        print("Loop-mounting raw image partitions...")
        with mount_image_partitions(cfg["img"]) as (_, mnt_dir, root_mnt):
            customize_image(mnt_dir, root_mnt, temp_dir, cfg["hostname"])

        print(f"\nSuccess! Prebaked image ready at: {cfg['img']}")
        print(f"Configured Static IP: {cfg['static_ip']}")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

if __name__ == "__main__":
    main()