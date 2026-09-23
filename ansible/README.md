# Ansible Configuration

This directory contains the automation playbooks for configuring Proxmox-managed infrastructure.

See the [project README](../README.md) for full documentation.

## Prerequisites

- **Ansible Core:** 2.14 or higher
- **Python:** 3.12+
- **Environment:** WSL2 / Linux / macOS

## Quick Start

```bash
# From the project root
make setup          # Create venv + install dependencies + vault
make ansible-install # Install Ansible collections

# Deploy services
make ansible-docker   # Docker host
make ansible-adguard  # AdGuard Home
```

## Vault (Secrets)

Secrets live in `group_vars/all/vault.yml` (gitignored). On first run `make setup` copies the template for you.

```bash
# Manually create if needed
make vault-create

# Edit with your values
$EDITOR group_vars/all/vault.yml
```

Required variables:

| Variable | Description |
|---|---|
| `admin_username` | Admin username for VMs and AdGuard dashboard |
| `adguard_admin_password_hash` | bcrypt hash of the AdGuard Home admin password |

Generate a bcrypt hash:

```bash
htpasswd -bnBC 10 "" 'yourpassword' | tr -d ':\n' | sed 's/$2y/$2a/'
```

## Manual Setup

```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate
pip install paramiko proxmoxer requests

# Install collections
ansible-galaxy install -r requirements.yml

# Run playbooks
ansible-playbook playbooks/install_docker.yml
ansible-playbook playbooks/install_adguard.yml
```

## AdGuard Home TLS

AdGuard Home runs with TLS enabled (`https://adguard.internal`). The first run of `playbooks/install_adguard.yml`:

1. Generates a self-signed certificate (RSA 2048, 825 days) with SAN `DNS:adguard.internal, IP:192.168.1.101` at `/opt/AdGuardHome/certs/` on the container.
2. Fetches a copy to `playbooks/files/cert.crt` on your machine so you can trust it locally (the directory is gitignored).

The dashboard stays reachable over plain HTTP too (`force_https: false`), so the cert only matters for HTTPS. Because the cert also carries the IP SAN, `https://192.168.1.101` works without warnings once the cert is trusted.

The certificate name and location are set via `adguard_tls_server_name` and `adguard_cert_directory` in `group_vars/role_adguard.yml`.

To **regenerate** the certificate, set `adguard_regenerate_cert: true` (extra vars or group_vars) and re-run the playbook:

```bash
ansible-playbook playbooks/install_adguard.yml -e adguard_regenerate_cert=true
```

This deletes the existing remote cert before regenerating; then re-trust the new `playbooks/files/cert.crt` on your machine.

To **trust the certificate on your machine**, see [Trusting the AdGuard TLS certificate](../docs/network-setup.md#trusting-the-adguard-tls-certificate).

## Docker Network

The Docker playbook creates a shared bridge network (`proxy-net`) used by nginx and application containers. Containers attached to this network can reach each other by container name, enabling service discovery without exposing ports on the host.
