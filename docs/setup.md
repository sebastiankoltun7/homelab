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

Managed via `make setup` — creates `ansible/.venv` with `ansible-core` + `paramiko` `proxmoxer` `requests` (`Makefile:37`). No global install required.

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

Used by `make ssh-cleanup` / `ssh-accept-keys` (`Makefile:112`) which cleans/accepts `192.168.1.100` (Proxmox), `192.168.1.102` (Docker VM) and `192.168.1.104` (K3s).

#### kubectl

Kubernetes CLI for the K3s cluster (`192.168.1.104`). Preferred via Make (Linux amd64, stable):

```bash
make kubectl-install   # curl stable.txt -> /usr/local/bin/kubectl
kubectl version --client
```

Manual alternatives:

```bash
# macOS
brew install kubectl

# Linux (Debian/Ubuntu) - manual equivalent of make kubectl-install
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl

# Windows
choco install kubernetes-cli

# Verify
kubectl version --client
```

Tested client `v1.37.1` (Kustomize `v5.8.1`) against server `v1.36.4+k3s1` (`kubectl get nodes`). Client/server skew of ±1 minor is supported; `stable.txt` may be newer. The kubeconfig itself is fetched by `ansible/playbooks/install_k3s.yml:35` to `ansible/playbooks/files/k3s.yaml` (gitignored via `.gitignore:36`) and wired locally via `make kubectl-config` / `make kubectl-setup` (see Verification > K3s).

#### Helm

Kubernetes package manager for deploying charts to the K3s cluster (`192.168.1.104`). Optional — only needed if you install chart-based apps. Preferred via Make (latest stable, SHA256-verified):

```bash
make helm-install     # runs the official get-helm-4 installer (prompts for sudo)
make helm-setup       # helm-install + `helm list -A` against the cluster (hard fail if unreachable)
helm version
```

`helm-install` is a thin wrapper around the [official `get-helm-4` script](https://helm.sh/docs/intro/install/#from-script), so platform detection, `curl`/`wget` fallback, SHA256 verification and the "already installed" check all come from upstream:

```make
curl -fsSL -o /tmp/get-helm-4 https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 /tmp/get-helm-4
/tmp/get-helm-4 $(if $(HELM_VERSION),--version $(HELM_VERSION))
```

It installs to `/usr/local/bin` and **prompts for your sudo password** — run it from an interactive terminal, not from CI. Re-running when the version already matches is a no-op (`Helm v4.3.0 is already latest`). Requires `openssl` (used for the checksum) and `tar`; the script reports either if missing.

Pin a specific version when you need reproducibility or want to stay on Helm 3 (the script adds a missing `v` prefix for you):

```bash
make helm-install HELM_VERSION=v3.22.0
```

To install without root, call the script directly with its own env vars:

```bash
USE_SUDO=false HELM_INSTALL_DIR=$HOME/.local/bin /tmp/get-helm-4
```

Manual alternatives:

```bash
# macOS
brew install helm

# Linux (Debian/Ubuntu) - official Helm project apt repo
HELM_BUILDKITE_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey > "${TMPDIR:-/tmp}/helm.gpg"
# Ensure that the key ID matches to prevent a repository compromise from establishing an attacker controlled key
if [ "$(gpg --show-keys --with-colons "${TMPDIR:-/tmp}/helm.gpg" | awk -F: '$1 == "fpr" {print $10}' | head -n 1)" != "${HELM_BUILDKITE_APT_KEY_ID}" ]; then echo "ERROR: Unexpected Helm APT key ID: potential key compromise"; exit 1; fi
cat "${TMPDIR:-/tmp}/helm.gpg" | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# Windows
choco install kubernetes-helm

# Verify
helm version
```

Tested `v4.3.0` (and `v3.22.0` for the pin path). `make helm-install` tracks the latest stable release, so it is not reproducible over time — pass `HELM_VERSION=` to pin. Upstream docs: <https://helm.sh/docs/intro/install/>.

> **Helm 4 vs 3:** Helm 4 defaults to server-side apply for new releases and renames a few flags (`--atomic` → `--rollback-on-failure`, `--force` → `--force-replace`, both deprecated with warnings). Releases created by Helm 3 keep client-side apply after an upgrade. Charts v2 work unchanged. If a chart or plugin misbehaves, re-run with `make helm-install HELM_VERSION=v3.22.0`.

> **Hardening:** `get-helm-4` verifies the SHA256 checksum by default (`VERIFY_CHECKSUM=true`) and supports detached GPG signature checks as well (`VERIFY_SIGNATURES=true`, needs `gpg` plus the maintainer keys from `curl https://raw.githubusercontent.com/helm/helm/main/KEYS | gpg --import`). To verify by hand instead:

> ```bash
> curl -LO https://get.helm.sh/helm-v4.3.0-linux-amd64.tar.gz
> curl -LO https://get.helm.sh/helm-v4.3.0-linux-amd64.tar.gz.asc
> gpg --verify helm-v4.3.0-linux-amd64.tar.gz.asc helm-v4.3.0-linux-amd64.tar.gz
> ```

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
make all            # Full deployment: ansible-pve → tf-init → tf-apply → ansible-pve-host → ansible-all (adguard + docker + plex + k3s)
# Opt-in local kubectl wiring (Linux):
make kubectl-setup  # install kubectl + copy kubeconfig -> ~/.kube/config
# Opt-in local Helm install:
make helm-setup     # install Helm (latest stable) + verify against the cluster
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
make tf-apply       # Create LXC and VMs (incl. K3s .104)
make ansible-install # Install Ansible collections (prefers .venv)
make ansible-all    # Configure services (runs ssh-accept-keys first, now includes k3s)
# Or single role:
make ansible-k3s    # K3s only
# Local kubectl (opt-in, Linux):
make kubectl-setup  # install kubectl + configure ~/.kube/config
# Local Helm (opt-in, any OS/arch):
make helm-setup     # install helm + `helm list -A` against the cluster
```

> `make ansible-adguard` / `make ansible-docker` / `make ansible-plex` / `make ansible-k3s` also run `ssh-accept-keys` automatically (.100, .102, .104). Only manual `ansible-playbook` needs `make ssh-cleanup`/`make ssh-accept-keys` separately.

### 3. What Happens

1. **Ansible (`ansible-pve`)** mounts each drive in `external_disks` at `/mnt/pve/<name>`
2. **Terraform** creates (via `terraform/main.tf:1`):
   - AdGuard LXC container (Debian 13, `terraform/modules/adguard_lxc:19`) at `192.168.1.101` (`local-lvm`, 512 MB, 1 core, tag `management-plane`)
   - Docker VM (Ubuntu 24.04 noble, `terraform/modules/docker_vm:9`) at `192.168.1.102` (10 GB boot + 50 GB data, 2–8 GB RAM)
   - Plex LXC container (Debian 13) at `192.168.1.103` with `/PlexMedia` + `/plex-config` bind mounts and `/dev/dri` GPU passthrough
   - K3s VM (Ubuntu 24.04 minimal, `terraform/modules/k3s_vm:1`) at `192.168.1.104` (10 GB boot + 30 GB `K3s-DATA`, 4 cores, 4–6 GB RAM, tags `k3s-node` + `role-k3s`, firewall 6443/10250/8472/80/443)
3. **Ansible** configures:
   - AdGuard Home DNS server with ad blocking + self-signed TLS (see `ansible/README.md` TLS section)
   - Docker engine with `proxy-net` bridge network, `containerd` root on data disk, weekly prune cron
   - Plex Media Server (config stored on the USB SSD)
   - K3s single-node control-plane (`ansible/playbooks/install_k3s.yml:1`, `INSTALL_K3S_EXEC="server --node-ip=192.168.1.104 --write-kubeconfig-mode 644"`, `inventory.yml:36` `role_k3s` -> `k3s-node` `192.168.1.104`, kubeconfig fetched to `ansible/playbooks/files/k3s.yaml` (`Makefile:14` `KUBECONFIG_SRC`, gitignored))

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

# Test internal DNS (rewrites in ansible/group_vars/role_adguard.yml:20)
nslookup adguard.internal 192.168.1.101
nslookup minio.docker.internal 192.168.1.101  # docker apps use *.docker.internal wildcard
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

### Check K3s / kubectl

K3s is deployed via `make ansible-k3s` (`ansible/playbooks/install_k3s.yml:1`, `terraform/modules/k3s_vm:1`). The playbook fetches the kubeconfig to `ansible/playbooks/files/k3s.yaml` (`Makefile:14` `KUBECONFIG_SRC`). The remote file contains `server: https://127.0.0.1:6443` and must be patched to the LAN IP before use.

**Opt-in Make path (Linux, recommended):**

```bash
make kubectl-setup   # install kubectl (stable) + patch 127.0.0.1 -> 192.168.1.104 + cp -> ~/.kube/config (600) + kubectl get nodes
# Equivalent step-by-step:
make kubectl-install # curl stable.txt -> /usr/local/bin/kubectl, then kubectl version --client
make kubectl-config  # sed + cp + chmod 600 + verify
```

**Manual equivalent (any OS after kubectl is installed):**

```bash
# 1. Fixup server IP (common pitfall: files/k3s.yaml does not exist; correct path is ansible/playbooks/files/k3s.yaml)
sed -i 's/127.0.0.1/192.168.1.104/g' ansible/playbooks/files/k3s.yaml

# 2. Install kubeconfig
mkdir -p ~/.kube
cp ansible/playbooks/files/k3s.yaml ~/.kube/config
chmod 600 ~/.kube/config

# 3. Verify (tested: Client v1.37.1 Kustomize v5.8.1 vs Server v1.36.4+k3s1)
kubectl version --client
kubectl get nodes
# Expected: NAME   STATUS   ROLES           AGE   VERSION
#           ubuntu Ready    control-plane   ...   v1.36.4+k3s1
kubectl cluster-info
kubectl get pods -A
```

> `ansible/playbooks/files/k3s.yaml` is gitignored (`.gitignore:36` `/ansible/playbooks/files/`). Do not commit it; if you need to run `sed` again it is idempotent. If `kubectl-config` reports `Missing ... Run 'make ansible-k3s' first`, the file hasn't been fetched yet.

### Check Helm

Helm talks to the same kubeconfig as `kubectl`, so `make kubectl-setup` must have run first. `make helm-install` only installs the binary; `make helm-setup` additionally verifies cluster access and fails if the cluster is unreachable.

```bash
make helm-setup   # helm-install + `helm list -A` (exits 1 if the cluster is not reachable)

# Equivalent step-by-step:
make helm-install
helm version
helm list -A                  # releases across all namespaces
helm repo list                # chart repositories (empty on a fresh install)
```

Adding a chart repository and installing a chart against the cluster:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm search repo cert-manager
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
helm list -A
```

Helm stores its state outside the kubeconfig in XDG directories — `~/.config/helm` (config, repos), `~/.cache/helm` (repository + chart cache), `~/.local/share/helm` (data). Removing the `helm` binary plus these three paths is a full uninstall. Override them with `$XDG_CONFIG_HOME`, `$XDG_CACHE_HOME`, `$XDG_DATA_HOME`; after changing the config path you must re-add repositories.

For a quick end-to-end check against a throwaway namespace:

```bash
helm create /tmp/demo && helm install demo /tmp/demo --dry-run | head
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
2. **Deploy apps** — See [Apps](../apps/README.md); add docker-compose files to `apps/docker/` (e.g., `nginx`, `mini_io`) — docker apps use `*.docker.internal` (`DOMAIN=docker.internal`, wildcard `*.docker.internal → 192.168.1.102` in `ansible/group_vars/role_adguard.yml:20`); Kubernetes apps via `make headlamp-install` on `192.168.1.104` (chart-based) or `kubectl apply -f` for raw manifests
3. **Add DNS rewrites** — Edit `ansible/group_vars/role_adguard.yml:20` (infrastructure hosts `adguard.internal`/`plex.internal` are explicit; docker apps are covered by the `*.docker.internal` wildcard; add `*.k8s.internal` -> `192.168.1.104` if you expose Traefik ingress)
4. **Wire kubectl (opt-in)** — `make kubectl-setup` (see Verification > K3s) then `kubectl get nodes` should show `v1.36.4+k3s1`
5. **Install Helm (opt-in)** — `make helm-setup` (see Verification > Helm) then `helm repo add <name> <url> && helm search repo <name>`. Only needed for chart-based Kubernetes apps.
6. **Retire the old Plex container (192.168.1.150)** — once 103 is verified, destroy the manually-created LXC 100 (`pct destroy 100`) and reclaim the orphaned `vm-100-disk-1` volume. It is not managed by Terraform.

## Troubleshooting

### SSH host key changed

After Terraform recreates a VM, SSH host keys change and connections fail with "Host key verification failed" or timeout.

```bash
make ssh-cleanup         # remove stale host keys (.100, .102, .104)
make ansible-docker      # reconnects with fresh keys (also runs ssh-accept-keys)
make ansible-k3s         # same for K3s .104
```

`make all` runs `ssh-cleanup` automatically before ansible, so this only affects manual `make ansible-*` runs on existing infrastructure.

### Manual SSH key acceptance

```bash
make ssh-accept-keys     # scan and add host keys to known_hosts (.100, .102, .104)
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

### K3s / kubectl issues

- **`sed: can't read files/k3s.yaml: No such file or directory`** — wrong path. Use `ansible/playbooks/files/k3s.yaml` (`Makefile:14` `KUBECONFIG_SRC`), not `files/k3s.yaml`. Or just run `make kubectl-config`.
- **`Missing ansible/playbooks/files/k3s.yaml. Run 'make ansible-k3s' first.`** — `make kubectl-config` guards this; the file is fetched by `ansible/playbooks/install_k3s.yml:35` via `fetch` (gitignored).
- **`kubectl get nodes` returns `Unable to connect to the server: dial tcp 127.0.0.1:6443`** — kubeconfig still points at loopback. Re-run `sed -i 's/127.0.0.1/192.168.1.104/g' ansible/playbooks/files/k3s.yaml` then `cp` to `~/.kube/config` (`make kubectl-config` does it atomically).
- **`kubectl: certificate signed by unknown authority`** — ensure `~/.kube/config` has `certificate-authority-data` from the fetched file; don't hand-edit. Re-fetch: `make ansible-k3s && make kubectl-config`.
- **`kubectl get nodes` shows NotReady** — SSH to `192.168.1.104` and `systemctl status k3s`, `journalctl -u k3s`, check firewall (`terraform/modules/k3s_vm:46` allows 6443/10250/8472). Verify `kubectl version --client` skew (tested `v1.37.1` vs `v1.36.4+k3s1`).
- **SSH timeout to K3s** — `make ssh-cleanup` now covers `.104` (`Makefile:112`); then `make ssh-accept-keys` or `make ansible-k3s`.

### Helm issues

- **`helm: command not found`** — not installed. `make helm-install` installs to `/usr/local/bin`; if you used the rootless variant (`USE_SUDO=false HELM_INSTALL_DIR=$HOME/.local/bin`), add that directory to `PATH`.
- **`sudo: a terminal is required to read the password`** — `make helm-install` shells out to `sudo`, which needs a TTY. Run it from an interactive terminal, or use the rootless variant above. Not usable from CI as-is.
- **`Please install openssl or set VERIFY_CHECKSUM=false`** — `get-helm-4` checksums via `openssl`. Install it (`sudo apt-get install -y openssl`) or accept the weaker `VERIFY_CHECKSUM=false`.
- **`No prebuilt binary for <os>-<arch>`** — your platform has no official build. `get-helm-4` lists the supported set (`darwin/linux/windows` × `amd64/arm64/386/arm/s390x/riscv64/ppc64le/loong64`); build from source otherwise.
- **`Expected version arg ('3.22.0') to begin with 'v', fixing...`** — informational, not an error. The script normalises `HELM_VERSION=3.22.0` to `v3.22.0` for you.
- **`Verifying checksum... FAILED`** — corrupt or tampered download; the script aborts and installs nothing. Re-run. Signature verification is described under Install Tools > Helm.
- **`Helm v4.3.0 is already latest`** — informational no-op, not an error. `get-helm-4` skips the download when the installed version already matches the target.
- **`helm list -A` reports `Kubernetes cluster unreachable`** — expected before `make kubectl-setup` has run; Helm uses the same `~/.kube/config`. `make helm-install` does not check the cluster, `make helm-setup` exits 1. Fix the kubeconfig first (see K3s / kubectl issues).
- **`helm list -A` fails with `x509: certificate signed by unknown authority`** — the kubeconfig is missing `certificate-authority-data`, i.e. a hand-edited or stale `~/.kube/config`. Re-copy it from the fetched file: `make ansible-k3s && make kubectl-config`.
- **`Error: Kubernetes cluster unreachable: tls: bad certificate`** or skew warnings on a chart install — a chart declaring a Kubernetes version constraint newer than the server (`v1.36.4+k3s1`). The `kubeVersion` field in `Chart.yaml` is a hard check, not a warning. Use a chart version compatible with 1.36, or upgrade the cluster.
- **A Helm 3 chart misbehaves under Helm 4** — Helm 4 changes the default apply method for *new* releases to server-side apply and renames `--atomic`/`--force`. Re-run with `make helm-install HELM_VERSION=v3.22.0` to compare behaviour. Note that `helm upgrade` follows the previous apply method of the release, so a Helm 3 release is unaffected until you pass `--server-side`.
- **Repository list is empty after changing `$XDG_CONFIG_HOME`** — Helm reads `~/.config/helm/repositories.yaml`; re-add repos with `helm repo add` after relocating config.
