# 🥧 Raspberry Pi Zero-Touch Image Baker

A lightweight, robust Python script designed to automatically download, configure, and prebake official **Raspberry Pi OS Lite** images. It implements **Day-0 configuration** using partition loop-mounting, cloud-init, and secure credentials fetched directly from Bitwarden—**requiring zero extra Python dependencies** by leveraging Python 3.12's native `tomllib`.

The Pi is standalone: it is not created by Terraform or configured by Ansible.

---

## Layout

The baker lives under `scripts/raspberry/`: the entry point, its settings file, and the cloud-init
templates it renders. It reuses the shared Bitwarden helper under `scripts/bitwarden/`.

The baker imports that helper as a module, so the repo's `scripts/` directory must be on
`PYTHONPATH` — run it from the repo root with `PYTHONPATH=scripts` set (see Usage).

---

## ⚙️ Configuration

All variables (hostname, timezone, static IP, gateway, and DNS servers) are isolated in the
baker's settings file so they never have to be hardcoded in the script:

| Setting | Default | Purpose |
| --- | --- | --- |
| `image_path` | `out/raspios-lite-arm64.img` | where the image lives, relative to the repo root |
| `username` | `skoltun` | default user created by cloud-init |
| `hostname` | `raspberry-pi` | device hostname |
| `timezone` | `Europe/Warsaw` | system timezone |
| `static_ip` | `192.168.1.105/24` | static address for the Pi |
| `gateway` | `192.168.1.1` | network gateway |
| `dns_servers` | `1.1.1.1`, `8.8.8.8` | resolvers written by cloud-init |

`out/` is gitignored — the baked image never lands in git. The default `static_ip` (`.105`) sits
inside the range you reserve for the lab in [Local Network Setup](../../docs/network-setup.md).

> **Pro Tip:** You can dynamically override any setting on the fly using environment variables without modifying the file (e.g. `PI_STATIC_IP="192.168.1.120/24"` in front of the run command). The full set is `PI_USER`, `PI_HOSTNAME`, `PI_TIMEZONE`, `PI_STATIC_IP`, `PI_GATEWAY`, `PI_DNS`.

---

## 🚀 Prerequisites

1. **Python 3.12+**.
2. **Bitwarden CLI (`bw`)** installed and authenticated (the script automatically checks for vault status and prompts for unlock if locked). It reads the SSH **public** key from the `homelab-ssh-key` item.
3. **Sudo Privileges** on your Linux host (required for `losetup`, partition mounting, and file injection).
4. **Core Utilities:** `curl`, `xz`, `losetup`, `mount`.

---

## 🛠 Usage

Run the baker from the repo root:

```bash
PYTHONPATH=scripts python3 scripts/raspberry/bake_image.py
```

Re-running is safe: an existing image is reused instead of re-downloaded, the cloud-init files are
rewritten from the current settings, and `cmdline.txt` is only extended when `cgroup_memory=1` is
missing.

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
