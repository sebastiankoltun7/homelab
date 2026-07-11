# Homelab

Infrastructure-as-Code repository for managing a Proxmox-based homelab. Provisioning is handled by Terraform; configuration management and application deployment by Ansible.

## Repository Structure

```
homelab/
├── ansible/                  # Configuration management
│   ├── ansible.cfg           # Ansible configuration
│   ├── group_vars/           # Group-specific variables
│   ├── inventory.yml         # Host inventory
│   ├── playbooks/            # Main playbooks
│   ├── requirements.yml      # Ansible collection dependencies
│   └── tasks/                # Reusable task files
├── apps/                     # Application configurations
│   ├── docker/               # Docker-based apps
│   └── k3s/                  # Kubernetes (planned)
├── terraform/                # Infrastructure provisioning
│   ├── main.tf               # Root module definitions
│   ├── providers.tf          # Provider configuration
│   ├── variables.tf          # Input variables
│   ├── terraform.tfvars.template
│   └── modules/              # Reusable Terraform modules
│       ├── proxmox_lxc/      # Base LXC module
│       ├── proxmox_vm/       # Base VM module
│       ├── adguard_lxc/      # AdGuard Home LXC
│       └── docker_vm/        # Docker host VM
└── Makefile                  # Setup and common commands
```

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| [Terraform](https://www.terraform.io/) | >= 1.0 | Infrastructure provisioning |
| [Ansible](https://www.ansible.com/) | >= 2.21 | Configuration management |
| [Python](https://www.python.org/) | >= 3.12 | Ansible runtime |
| [Make](https://www.gnu.org/software/make/) | any | Task automation |

### Python Packages (for Ansible)

The following Python packages are required by Ansible collections:

| Package | Purpose |
|---------|---------|
| `paramiko` | SSH connections (Proxmox LXC) |
| `proxmoxer` | Proxmox REST API client |
| `requests` | HTTP library for API calls |

### Ansible Collections

| Collection | Version | Purpose |
|------------|---------|---------|
| `ansible.posix` | 2.2.0 | POSIX system modules |
| `community.general` | 13.0.1 | General-purpose modules |
| `community.proxmox` | 2.0.0 | Proxmox management |

## Quick Start

```bash
# 1. Clone the repository
git clone <repository-url> homelab
cd homelab

# 2. Run automated setup (installs all dependencies)
make setup

# 3. Configure Terraform credentials
cp terraform/terraform.tfvars.template terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your Proxmox credentials
```

## Usage

### Terraform

```bash
# Initialize providers and modules
make tf-init

# Preview infrastructure changes
make tf-plan

# Apply infrastructure changes
make tf-apply

# Destroy infrastructure
make tf-destroy
```

### Ansible

```bash
# Install Ansible collection dependencies
make ansible-install

# Deploy Docker host
make ansible-docker

# Deploy AdGuard Home
make ansible-adguard

# Run all playbooks
make ansible-all

# Dry-run (check mode)
make ansible-dry-run
```

### Combined

```bash
# Full setup: Terraform + Ansible
make all
```
