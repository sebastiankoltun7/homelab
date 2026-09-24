# Initial Setup Guide

Step-by-step guide to set up the homelab from scratch.

## Prerequisites

### Install Tools

#### Terraform

```bash
# macOS
brew install terraform

# Linux (Debian/Ubuntu)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Windows
choco install terraform
```

Verify: `terraform version` (tested 1.16.x, see `terraform.tfstate:3`).

#### Ansible

Managed via `make setup` — creates `ansible/.venv` with `ansible-core` + `paramiko` `proxmoxer` `requests` (`Makefile:26`). No global install required.

```bash
# Alternative: global install
pip install ansible-core
sudo apt install ansible  # Ubuntu (may be older)
```

Collections are pinned in `ansible/requirements.yml:1` (`ansible.posix 2.2.0`, `community.docker 5.2.1`, `community.general 13.0.1`, `community.proxmox 2.0.0`) and installed by `make ansible-install`.

#### Docker

```bash
# macOS
brew install --cask docker

# Linux (Debian/Ubuntu)
sudo apt install docker.io

# Windows
choco install docker-desktop
```

#### Python 3.12+

```bash
# macOS
brew install python@3.12

# Linux (Debian/Ubuntu)
sudo apt install python3.12 python3.12-venv

# Windows
choco install python
```

`make setup` uses `python3` to create the venv. Ensure `python3 --version` is 3.12+.

#### Make

```bash
# macOS
xcode-select --install

# Linux (Debian/Ubuntu)
sudo apt install make

# Windows (Git Bash includes make, or)
choco install make
```

#### OpenSSH

Usually pre-installed on all platforms. Verify with:

```bash
ssh -V
ssh-keygen -V
```

Used by `make ssh-cleanup` / `ssh-accept-keys` (`Makefile:78`) which cleans both `192.168.1.100` (Proxmox) and `192.168.1.102` (Docker VM).

### Proxmox Setup

#### 1. Enable API Token Authentication

1. Log in to Proxmox web UI (https://PROXMOX_IP:8006)
2. Go to **Datacenter** > **Permissions** > **API Tokens**
3. Click **Add**
4. Select a user (or create one, e.g., `terraform@pam`)
5. Check **Privilege Separation: No** (allows full API access)
6. Note the **Token ID** and **Token Secret**

#### 2. Generate SSH Key Pair and Add to Proxmox Host

Generate an SSH key pair for Proxmox and VM access, then copy it to the Proxmox host (Terraform and Ansible need it):

```bash
# Generate key (if you don't have one)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Copy public key to Proxmox host (choose one)
ssh-copy-id root@192.168.1.100
# Or manually:
cat ~/.ssh/id_ed25519.pub | ssh root@192.168.1.100 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

Verify: `ssh root@192.168.1.100` should succeed without password.

## Configuration

### 1. Run Setup

```bash
make setup
```

This creates:
- Python virtual environment at `ansible/.venv` with `ansible-core` + deps
- Ansible collections (`make ansible-install`)
- Config files from templates (skips if they exist): `terraform/terraform.tfvars`, `ansible/group_vars/all/vault.yml`

Activate the venv for direct ansible use:

```bash
source ansible/.venv/bin/activate
ansible-playbook --version
```

### 2. Configure Terraform

**Local state storage:** By default, Terraform state is stored in Terraform Cloud (`terraform/providers.tf:8` `cloud` block). To use local state instead, remove the `cloud` block:

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}
```

> Version `0.108.0` is pinned in `terraform/providers.tf:5` and `terraform/.terraform.lock.hcl:5`. Run `terraform init -upgrade` after bumping.

State file `terraform.tfstate` is gitignored (`.gitignore:3`). The repo ships an empty placeholder.

Edit `terraform/terraform.tfvars` (copied from `terraform/terraform.tfvars.template:1`):

```hcl
proxmox = {
  ip                    = "192.168.1.100"    # Proxmox host IP
  port                  = "8006"             # Proxmox API port
  username              = "tf-infra@pve!tf"          # dedicated, least-privilege API user
  api_token             = "tf-infra@pve!tf=xxxxxxxx" # Token secret value
  root_ssh_key_location = "~/.ssh/id_ed25519" # SSH private key path
  insecure              = true               # Skip TLS verification (default: true)
  ssh_username          = "root"             # SSH username for Proxmox (default: "root")
  node_name             = "pve"              # Proxmox node name (default: "pve")
}
vm_ssh_pub_key    = "ssh-ed25519 AAAA..."     # Public key for VMs
admin_username    = "your-username"            # Admin user for all services
```

> **API user:** use a dedicated automation user, **never** `root@pam`. Create it with the
> `Administrator` role on `/` (token must be `--privsep 0` so it inherits the user's ACLs):
>
> ```bash
> pveum user add tf-infra@pve --enable 1
> pveum aclmod / -user tf-infra@pve -role Administrator
> pveum user token add tf-infra@pve tf --privsep 0
> ```
>
> The `Administrator` role is **required** (narrower scopes break Terraform):
> - Per-VMID paths (`/vms/<id>`) cannot cover VMIDs that do not exist yet, so creating a new host 403s.
> - Image/URL downloads need node-level privileges: `query-url-metadata` and `download-url` require
>   `Sys.Audit` **and** `Sys.Modify` on `/` (PVE `perm` privilege lists are ANDed) or
>   `Sys.AccessNetwork` on `/nodes/<node>` — neither is covered by `PVEAdmin`/`PVEVMAdmin`.
>
> Bind mounts and device passthrough on LXC can only be applied by `root@pam` itself
> (no API token, not even a root one); those are handled out-of-band by the
> `ansible-pve-host` playbook over SSH.

**Fields explained:**

| Field | Description |
|-------|-------------|
| `proxmox.ip` | Proxmox host IP address |
| `proxmox.port` | Proxmox web UI port (default: 8006) |
| `proxmox.username` | API token in format `user@realm!token-id` (dedicated automation user with `Administrator` role; not `root@pam`) |
| `proxmox.api_token` | Token secret from Proxmox UI |
| `proxmox.root_ssh_key_location` | Path to SSH private key for Proxmox/VM access |
| `proxmox.insecure` | Skip TLS verification (default: true) |
| `proxmox.ssh_username` | SSH username for Proxmox host (default: "root") |
| `proxmox.node_name` | Proxmox node name (default: "pve") |
| `vm_ssh_pub_key` | Public key deployed to created VMs/LXC (via `terraform/modules/proxmox_lxc` / `proxmox_vm`) |
| `admin_username` | Username created on VMs and used for services (must match vault) |

See `terraform/variables.tf:1` for types/defaults.

### 3. Configure Ansible Vault

Edit `ansible/group_vars/all/vault.yml` (created from `ansible/vault.yml.template:1`, gitignored via `.gitignore:24`):

```yaml
admin_username: "your-username"
adguard_admin_password_hash: "$2a$10$..."  # bcrypt hash
```

**Generate bcrypt hash:**

```bash
# Install htpasswd (usually pre-installed on macOS/Linux)
# macOS
brew install httpd

# Linux
sudo apt install apache2-utils

# Generate hash (AdGuard expects $2a$)
htpasswd -bnBC 10 "" 'yourpassword' | tr -d ':\n' | sed 's/$2y/$2a/'
```

**Note:** `admin_username` must match the value in `terraform.tfvars`.

Vault variables are used in `ansible/group_vars/role_adguard.yml:8` (`adguard_admin_username`) and `ansible/group_vars/role_docker.yml:2`.

### 4. Configure External USB Disks

Edit `ansible/group_vars/pve.yml` and point `external_disks[].by_id` at the drive to mount. Find the stable by-id name on the Proxmox host:

```bash
ssh root@192.168.1.100 "ls -l /dev/disk/by-id/ | grep -i usb"
```

Example:

```yaml
external_disks:
  - name: ssd-backup
    by_id: "usb-Samsung_PSSD_T7_S4XXNXXX-0:0"
    opts: "defaults"
    dir_mode: "0777"
    assert_dirs: [PlexMedia]
    create_dirs: [PlexConfig]
```

`make all` detects the drive's UUID/filesystem automatically and mounts it persistently (fstab by UUID) at `/mnt/pve/<name>` before Terraform creates the containers. `assert_dirs` must already exist on the drive (media), `create_dirs` is created if missing (used for the Plex config bind mount).

## First Deployment

### 1. Preview Changes

```bash
make tf-plan        # Preview infrastructure changes (terraform plan)
```

### 2. Deploy Infrastructure

```bash
make all            # Full deployment: tf-init → tf-apply → ansible-install → ssh-cleanup → ansible-all
```

If this is a fresh deployment you need to do two one-time state steps first (local only, no infra changes):

```bash
# 1. Shift the shared OS template resource address (module was extended with `count`)
terraform state mv 'module.adguard_home.module.adguard_lxc.proxmox_virtual_environment_file.debian_template' 'module.adguard_home.module.adguard_lxc.proxmox_virtual_environment_file.debian_template[0]'

# 2. (optional) Preview that Terraform only ADDS the new plex container
make tf-plan
```

Or step by step:

```bash
make tf-init        # Initialize Terraform
make tf-apply       # Create LXC and VM
make ansible-install # Install Ansible collections (prefers .venv)
make ansible-all    # Configure services (runs ssh-accept-keys first)
```

> `make ansible-adguard` / `make ansible-docker` also run `ssh-accept-keys` automatically. Only manual `ansible-playbook` needs `make ssh-cleanup`/`make ssh-accept-keys` separately.

### 3. What Happens

1. **Ansible (`ansible-pve`)** mounts each drive in `external_disks` at `/mnt/pve/<name>`
2. **Terraform** creates (via `terraform/main.tf:1`):
   - AdGuard LXC container (Debian 13, `terraform/modules/adguard_lxc:19`) at `192.168.1.101` (`local-lvm`, 512 MB, 1 core, tag `management-plane`)
   - Docker VM (Ubuntu 24.04 noble, `terraform/modules/docker_vm:9`) at `192.168.1.102` (10 GB boot + 50 GB data, 2–8 GB RAM)
   - Plex LXC container (Debian 13) at `192.168.1.103` with `/PlexMedia` + `/plex-config` bind mounts and `/dev/dri` GPU passthrough
3. **Ansible** configures:
   - AdGuard Home DNS server with ad blocking + self-signed TLS (see `ansible/README.md` TLS section)
   - Docker engine with `proxy-net` bridge network, `containerd` root on data disk, weekly prune cron
   - Plex Media Server (config stored on the USB SSD)

### 4. First-time Plex setup

After the first `make all`, claim the server once from a browser:

1. Open `http://192.168.1.103:32400/web` and sign in
2. Add libraries pointing at `/PlexMedia` (Movies / Shows)

## Verification

### Check Infrastructure

```bash
# Proxmox - verify VMs are running
# Web UI: https://192.168.1.100:8006

# SSH into Docker VM
ssh your-username@192.168.1.102

# Check Docker is running
docker info
```

### Check AdGuard

```bash
# Open dashboard
open http://192.168.1.101

# Test DNS resolution
nslookup google.com 192.168.1.101

# Test internal DNS ( rewrites in ansible/group_vars/role_adguard.yml:9 )
nslookup adguard.internal 192.168.1.101
```

### Check Plex

```bash
# Verify container mounts (binds + USB)
ssh root@192.168.1.103 "findmnt /PlexMedia /plex-config && ls /dev/dri"

# Open web UI
open http://192.168.1.103:32400/web

# Via AdGuard DNS
open http://plex.internal:32400/web
```

### Check Docker Context

```bash
# Setup remote Docker context (uses DOCKER_USER ?= skoltun, DOCKER_HOST_IP 192.168.1.102)
make docker-context

# Test
docker ps
```

Override user if needed: `make docker-context DOCKER_USER=myuser`.

## Next Steps

1. **Configure client DNS** — See [Local Network Setup](network-setup.md)
2. **Deploy apps** — See [Apps](../apps/README.md); add docker-compose files to `apps/docker/` (e.g., `nginx`, `mini_io`)
3. **Add DNS rewrites** — Edit `ansible/group_vars/role_adguard.yml:9`
4. **Retire the old Plex container (192.168.1.150)** — once 103 is verified, destroy the manually-created LXC 100 (`pct destroy 100`) and reclaim the orphaned `vm-100-disk-1` volume. It is not managed by Terraform.

## Troubleshooting

### SSH host key changed

After Terraform recreates a VM, SSH host keys change and connections fail with "Host key verification failed" or timeout.

```bash
make ssh-cleanup         # remove stale host keys (.100, .102)
make ansible-docker      # reconnects with fresh keys (also runs ssh-accept-keys)
```

`make all` runs `ssh-cleanup` automatically before ansible, so this only affects manual `make ansible-*` runs on existing infrastructure.

### Manual SSH key acceptance

```bash
make ssh-accept-keys     # scan and add host keys to known_hosts (.100, .102)
```

### Terraform fails to connect to Proxmox

- Verify API token credentials in `terraform.tfvars`
- Check Proxmox IP and port are reachable: `curl -k https://192.168.1.100:8006`
- Ensure Proxmox node name (`pve`) matches your cluster

### Ansible SSH timeout

- Run `make ssh-cleanup` to remove stale host keys
- Verify SSH key is on Proxmox host: `ssh root@192.168.1.100`
- AdGuard LXC is reached via `community.proxmox.proxmox_pct_remote` (`ansible/inventory.yml:13`), not direct SSH to `.101`

### AdGuard dashboard unreachable

- Check LXC is running in Proxmox UI
- Verify port 80 is not blocked: `curl http://192.168.1.101`
- Check TLS cert at `/opt/AdGuardHome/certs/` (`ansible/playbooks/install_adguard.yml:52`)

### Docker VM not accessible

- Check VM is running in Proxmox UI
- Verify SSH key matches: `ssh -i ~/.ssh/id_ed25519 your-username@192.168.1.102`
- Check data disk mount: `lsblk` / `mount | grep docker-data` (`ansible/group_vars/role_docker.yml:5`)
