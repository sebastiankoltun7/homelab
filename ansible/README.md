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
make ansible-all      # both (runs ssh-accept-keys first)
make ansible-dry-run  # check mode
```

`make ansible-*` targets automatically run `ssh-accept-keys` (`Makefile:58`). `make all` also runs `ssh-cleanup` before ansible.

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
```

Pinned collections: see `requirements.yml:1` — `ansible.posix 2.2.0`, `community.docker 5.2.1`, `community.general 13.0.1`, `community.proxmox 2.0.0`.

## Inventory

- `role_docker` → `docker-host` `192.168.1.102` via SSH as `{{ admin_username }}` (`group_vars/role_docker.yml:2`)
- `role_adguard` → `adguard-host` Proxmox host `192.168.1.100` via `community.proxmox.proxmox_pct_remote` (`inventory.yml:13`, `proxmox_vmid: 101`)

The AdGuard LXC is not SSHed directly; Ansible tunnels via Proxmox.

## AdGuard Home TLS

AdGuard Home runs with TLS enabled (`https://adguard.internal`, `AdGuardHome.yml.j2:4`). The first run of `playbooks/install_adguard.yml:52`:

1. Generates a self-signed certificate (RSA 2048, 825 days) with SAN `DNS:adguard.internal, IP:192.168.1.101` at `/opt/AdGuardHome/certs/` on the container.
2. Fetches a copy to `playbooks/files/cert.crt` on your machine so you can trust it locally (the directory is gitignored via `../.gitignore:35`).

The dashboard stays reachable over plain HTTP too (`force_https: false`), so the cert only matters for HTTPS. Because the cert also carries the IP SAN, `https://192.168.1.101` works without warnings once the cert is trusted.

The certificate name and location are set via `adguard_tls_server_name` and `adguard_cert_directory` in `group_vars/role_adguard.yml:5`.

To **regenerate** the certificate, set `adguard_regenerate_cert: true` (extra vars or group_vars) and re-run the playbook:

```bash
ansible-playbook playbooks/install_adguard.yml -e adguard_regenerate_cert=true
```

This deletes the existing remote cert before regenerating; then re-trust the new `playbooks/files/cert.crt` on your machine.

To **trust the certificate on your machine**, see [Trusting the AdGuard TLS certificate](../docs/network-setup.md#trusting-the-adguard-tls-certificate).

## Docker Network & Host

The Docker playbook (`playbooks/install_docker.yml:58`) creates a shared bridge network (`proxy-net`) used by nginx and application containers. Containers attached to this network can reach each other by container name, enabling service discovery without exposing ports on the host.

Host config: data disk `virtio-DOCKER-DATA` mounted at `/mnt/docker-data` (`group_vars/role_docker.yml:5`), Docker `data-root` and `containerd` root on that mount, weekly prune cron Sunday 01:00 (`group_vars/role_docker.yml:21`, `tasks/docker_cleanup_cron.yml:14`), `geerlingguy.docker` role for engine + compose plugin.
