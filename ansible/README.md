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

## Docker Network

The Docker playbook creates a shared bridge network (`proxy-net`) used by nginx and application containers. Containers attached to this network can reach each other by container name, enabling service discovery without exposing ports on the host.
