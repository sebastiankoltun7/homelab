# 🥧 Raspberry Pi Zero-Touch Image Baker

A lightweight, robust Python script designed to automatically download, configure, and prebake official **Raspberry Pi OS Lite** images. It implements **Day-0 configuration** using partition loop-mounting, cloud-init, and secure credentials fetched directly from Bitwarden—**requiring zero extra Python dependencies** by leveraging Python 3.12's native `tomllib`.

The Pi is standalone: it is not created by Terraform or configured by Ansible.

---

## 📂 Directory Structure

```text
scripts/
├── bitwarden/
│   ├── bitwarden_get.py      # shared Bitwarden helper (also used by the mise tasks)
│   └── __init__.py
└── raspberry/
    ├── bake_image.py         # Main prebaker script
    ├── config.toml           # Single source of truth for host and network settings
    ├── __init__.py
    └── templates/            # Cloud-init templates
        ├── meta-data.template
        ├── network-config.template
        └── user-data.template
```

`bake_image.py` imports `bitwarden.bitwarden_get`, so the repo's `scripts/` directory must be on
`PYTHONPATH`. [`.mise.toml`](../../.mise.toml) sets `PYTHONPATH = "scripts"`, which is why
`mise run bake-image` works and a bare `python3 scripts/raspberry/bake_image.py` may not. Outside
mise, either run it through `mise exec -- python3 scripts/raspberry/bake_image.py` or prefix
`PYTHONPATH=scripts`.

---

## ⚙️ Configuration (`config.toml`)

All variables (hostname, timezone, static IP, gateway, and DNS servers) are isolated in `config.toml` so they never have to be hardcoded in the script:

```toml
[pi]
image_path = "out/raspios-lite-arm64.img"
username = "skoltun"
hostname = "raspberry-pi"
timezone = "Europe/Warsaw"

[network]
static_ip = "192.168.1.105/24"
gateway = "192.168.1.1"
dns_servers = ["1.1.1.1", "8.8.8.8"]
```

`image_path` is relative to the repo root, and `out/` is gitignored — the baked image never lands in
git. The default `static_ip` (`.105`) sits inside the range you reserve for the lab in
[Local Network Setup](../../docs/network-setup.md).

> **Pro Tip:** You can dynamically override any setting on the fly using environment variables without modifying the file (e.g., `PI_STATIC_IP="192.168.1.120/24" mise run bake-image`). The full set is `PI_USER`, `PI_HOSTNAME`, `PI_TIMEZONE`, `PI_STATIC_IP`, `PI_GATEWAY`, `PI_DNS`.

---

## 🚀 Prerequisites

1. **Python 3.12+** (managed smoothly via your project's `.mise.toml`).
2. **Bitwarden CLI (`bw`)** installed and authenticated (the script automatically checks for vault status and prompts for unlock if locked). It reads the SSH **public** key from the `homelab-ssh-key` item.
3. **Sudo Privileges** on your Linux host (required for `losetup`, partition mounting, and file injection).
4. **Core Utilities:** `curl`, `xz`, `losetup`, `mount`.

---

## 🛠 Usage

Run the build task via `mise` — it sets up `PYTHONPATH` for you:

```bash
mise run bake-image
```

Or execute the Python script directly from the repo root:

```bash
mise exec -- python3 scripts/raspberry/bake_image.py
```

The script is idempotent about the download (an existing image is reused) but not about patching: it
detects the cloud-init files it already injected, and `cmdline.txt` is only extended when
`cgroup_memory=1` is missing.

---

## 🔍 What Happens Under the Hood?

1. **Image Acquisition:** Checks if the target `.img` exists. If missing, it downloads the latest official Raspberry Pi OS Lite image and decompresses it automatically.
2. **Secret Retrieval:** Connects to your local Bitwarden vault to fetch your pinned SSH public key (`homelab-ssh-key`).
3. **Template Rendering:** Substitutes your configuration values into the `cloud-init` templates (`user-data`, `meta-data`, `network-config`).
4. **Loop Mounting & Patching:**
    * Mounts the boot partition (`p1`) to inject cloud-init files and create an empty `ssh` flag file to enable SSH by default.
    * Patches `cmdline.txt` to explicitly enable **memory cgroups** (`cgroup_memory=1 cgroup_enable=memory`), making the node container-ready for Docker and K3s.
    * Mounts the root partition (`p2`) to clean up unnecessary files and write a custom startup MOTD banner.
5. **Safe Cleanup:** Unmounts all partitions and detaches the loop device cleanly, leaving you with a fully prebaked image ready to flash via Balena Etcher, Raspberry Pi Imager, or `dd`.