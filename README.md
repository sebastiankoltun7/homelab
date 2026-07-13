# Homelab

Proxmox VE homelab managed with Terraform and Ansible. Single `make all` provisions infrastructure, configures hosts, and deploys apps.

## Quick Start

```bash
make setup                                          # venv + dependencies + vault
cp terraform/terraform.tfvars.template terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with Proxmox credentials
# Edit ansible/group_vars/all/vault.yml with secrets
make all                                            # full deployment
```

## Commands

```bash
make help                # list all targets
make tf-plan             # preview infrastructure
make tf-apply            # apply infrastructure
make ansible-adguard     # deploy AdGuard Home
make ansible-docker      # deploy Docker host
make ansible-dry-run     # check mode all playbooks
make docker-context      # remote Docker context setup
make clean               # remove venv
```

## Infrastructure

| Host | Type | IP | Purpose |
|------|------|----|---------|
| adguard | LXC (Debian 13) | 192.168.1.101 | DNS ad blocking |
| docker | VM (Ubuntu 24.04) | 192.168.1.102 | Container runtime |

## Prerequisites

- Terraform >= 1.0
- Ansible >= 2.21
- Docker >= 24.0
- Python >= 3.12
- Make
