# Ansible Configuration

This directory contains the automation playbooks for configuring Proxmox-managed infrastructure.

See the [project README](../README.md) and [Initial Setup](../docs/setup.md) for full provisioning flow.

## Prerequisites

- **Ansible Core:** 2.14 or higher (auto-installed into `.venv` by `make setup`)
- **Python:** 3.12+
- **Environment:** WSL2 / Linux / macOS

## Quick Start

```bash
# From the project root
make setup            # create .venv + install ansible-core + collections + vault
make ansible-install  # re-install collections (uses .venv if present)

# Activate venv for direct usage
source ansible/.venv/bin/activate

# Deploy services
make ansible-docker   # Docker host (192.168.1.102, user {{ admin_username }})
make ansible-adguard  # AdGuard Home (LXC 101 via Proxmox API)
make ansible-plex     # Plex Media Server (LXC 103 via Proxmox API)
make ansible-k3s      # K3s single-node (192.168.1.104, user {{ admin_username }})
make ansible-all      # all (adguard + docker + plex + k3s, runs ssh-accept-keys first)
make ansible-dry-run  # check mode
# Local kubectl (opt-in, Linux):
make kubectl-setup    # install kubectl + configure ~/.kube/config from ansible/playbooks/files/k3s.yaml
```

`make ansible-*` targets automatically run `ssh-accept-keys` (`Makefile:102`) which covers `.100`, `.102`, `.104`. `make all` also runs `ssh-cleanup` before ansible (`Makefile:98`).

## Vault (Secrets)

Secrets live in `group_vars/all/vault.yml` (gitignored via `../.gitignore:24`). On first run `make setup` copies the template for you.

```bash
# Manually create if needed
make vault-create

# Edit with your values
$EDITOR ansible/group_vars/all/vault.yml
```

Required variables:

| Variable | Description |
|---|---|
| `admin_username` | Admin username for VMs and AdGuard dashboard (must match `terraform.tfvars`) |
| `adguard_admin_password_hash` | bcrypt hash of the AdGuard Home admin password |

Generate a bcrypt hash:

```bash
htpasswd -bnBC 10 "" 'yourpassword' | tr -d ':\n' | sed 's/$2y/$2a/'
```

## Manual Setup (without Make)

```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install ansible-core paramiko proxmoxer requests

# Install collections (uses .venv's ansible-galaxy if present)
ansible-galaxy install -r requirements.yml --force
# or
.venv/bin/ansible-galaxy install -r requirements.yml --force

# Run playbooks (ensure known_hosts or use Makefile's ssh-accept-keys)
ansible-playbook playbooks/install_docker.yml
ansible-playbook playbooks/install_adguard.yml
ansible-playbook playbooks/install_plex.yml
ansible-playbook playbooks/install_k3s.yml
```

Pinned collections: see `requirements.yml:1` — `ansible.posix 2.2.0`, `community.docker 5.2.1`, `community.general 13.0.1`, `community.proxmox 2.0.0`.

## Inventory

- `role_docker` → `docker-host` `192.168.1.102` via SSH as `{{ admin_username }}` (`group_vars/role_docker.yml:2`)
- `role_adguard` → `adguard-host` Proxmox host `192.168.1.100` via `community.proxmox.proxmox_pct_remote` (`inventory.yml:13`, `proxmox_vmid: 101`)
- `role_plex` → `plex-host` Proxmox host `192.168.1.100` via `community.proxmox.proxmox_pct_remote` (`inventory.yml:27`, `proxmox_vmid: 103`)
- `role_k3s` → `k3s-node` `192.168.1.104` via SSH as `{{ admin_username }}` (`inventory.yml:36`, `group_vars/role_k3s.yml:1`)

The AdGuard/Plex LXC containers are not SSHed directly; Ansible tunnels via Proxmox. K3s is a VM reached directly over SSH.

## AdGuard Home TLS

AdGuard Home runs with TLS enabled (`https://adguard.internal`, `adguard/AdGuardHome.yml.j2:4`). The first run of `playbooks/install_adguard.yml:52`:

1. Renders `playbooks/adguard/openssl.cnf.j2` to `/opt/AdGuardHome/certs/openssl.cnf` and generates a self-signed certificate (RSA 2048, 825 days) at `/opt/AdGuardHome/certs/` on the container. SANs are templated from `group_vars/role_adguard.yml:9` (`adguard_alt_names`: `*.docker.internal`, `docker.internal`, `*.internal`, `internal`, `*.k8s.internal`, etc. + `adguard_alt_ips`: `192.168.1.101`), with CN `{{ adguard_tls_server_name }}` (`adguard.internal`).
2. Fetches a copy to `playbooks/files/cert.crt` on your machine so you can trust it locally (the directory is gitignored via `../.gitignore:35`).

The dashboard stays reachable over plain HTTP too (`force_https: false`), so the cert only matters for HTTPS. Because the cert also carries the IP SAN, `https://192.168.1.101` and any `*.docker.internal` host work without warnings once the cert is trusted.

The certificate name and location are set via `adguard_tls_server_name` and `adguard_cert_directory` in `group_vars/role_adguard.yml:5`; SANs via `adguard_alt_names` / `adguard_alt_ips` (`group_vars/role_adguard.yml:9`).

To **regenerate** the certificate, set `adguard_regenerate_cert: true` (extra vars or group_vars) and re-run the playbook:

```bash
ansible-playbook playbooks/install_adguard.yml -e adguard_regenerate_cert=true
```

This deletes the existing remote cert before regenerating; then re-trust the new `playbooks/files/cert.crt` on your machine.

To **trust the certificate on your machine**, see [Trusting the AdGuard TLS certificate](../docs/network-setup.md#trusting-the-adguard-tls-certificate).

## Docker Network & Host

The Docker playbook (`playbooks/install_docker.yml:58`) creates a shared bridge network (`proxy-net`) used by nginx and application containers. Containers attached to this network can reach each other by container name, enabling service discovery without exposing ports on the host.

Host config: data disk `virtio-DOCKER-DATA` mounted at `/mnt/docker-data` (`group_vars/role_docker.yml:5`), Docker `data-root` and `containerd` root on that mount, weekly prune cron Sunday 01:00 (`group_vars/role_docker.yml:21`, `tasks/docker_cleanup_cron.yml:14`), `geerlingguy.docker` role for engine + compose plugin.

## K3s & kubeconfig

The K3s playbook (`playbooks/install_k3s.yml:1`, `terraform/modules/k3s_vm:1`) provisions a single-node control-plane VM `192.168.1.104` (`inventory.yml:36` `role_k3s`):

1. Checks `/usr/local/bin/k3s`; if absent runs `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip=192.168.1.104 --write-kubeconfig-mode 644" sh -` (`playbooks/install_k3s.yml:9`).
2. Ensures `k3s` systemd service is started/enabled, `k3s.yaml` mode `0644`, then `fetch`es `/etc/rancher/k3s/k3s.yaml` to `playbooks/files/k3s.yaml` (`playbooks/install_k3s.yml:35`, flat).
3. That fetched file is gitignored via `.gitignore:36` (`/ansible/playbooks/files/`) and contains `server: https://127.0.0.1:6443` — patch it before use.

Local wiring (Linux, opt-in):

```bash
make kubectl-setup    # install kubectl (stable) + patch 127.0.0.1 -> 192.168.1.104 + cp -> ~/.kube/config (600)
# Or granular:
make kubectl-install  # curl stable.txt -> /usr/local/bin/kubectl (tested v1.37.1, Kustomize v5.8.1 vs v1.36.4+k3s1)
make kubectl-config   # sed -i 's/127.0.0.1/192.168.1.104/g' files, cp to ~/.kube/config, chmod 600, verify
kubectl get nodes     # ubuntu Ready control-plane v1.36.4+k3s1
kubectl cluster-info && kubectl get pods -A
```

Manual fallback (macOS `brew install kubectl`, Windows `choco install kubernetes-cli`) then the same `sed` + `cp` + `chmod 600` steps; see `docs/setup.md` Verification > K3s. Firewall for K3s is in `terraform/modules/k3s_vm:46` (ingress 6443/10250/8472/80/443, DNS egress to `192.168.1.101`).
