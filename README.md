# Homelab

Proxmox VE homelab managed with Terraform and Ansible. Single `make all` provisions infrastructure, configures hosts, and deploys apps.

## Quick Start

```bash
make setup                                          # venv + config templates
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

## Documentation

- [Initial Setup](docs/setup.md) - Prerequisites, Proxmox config, first deployment, troubleshooting
- [Local Network Setup](docs/network-setup.md) - DNS configuration, client setup, troubleshooting

## Prerequisites

- Terraform >= 1.0
- Ansible Core >= 2.14
- Docker >= 24.0
- Python >= 3.12
- Make
- OpenSSH (for ssh-cleanup and ssh-accept-keys)
