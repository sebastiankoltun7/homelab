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

## Troubleshooting

### SSH host key changed

After Terraform recreates a VM, SSH host keys change and connections fail with "Host key verification failed" or timeout.

```bash
make ssh-cleanup         # remove stale host keys
make ansible-docker      # reconnects with fresh keys
```

`make all` runs `ssh-cleanup` automatically before ansible, so this only affects manual `make ansible-*` runs on existing infrastructure.

### Manual SSH key acceptance

```bash
make ssh-accept-keys     # scan and add host keys to known_hosts
```

## Infrastructure

| Host | Type | IP | Purpose |
|------|------|----|---------|
| adguard | LXC (Debian 13) | 192.168.1.101 | DNS ad blocking |
| docker | VM (Ubuntu 24.04) | 192.168.1.102 | Container runtime |

## Documentation

- [Initial Setup](docs/setup.md) - Prerequisites, Proxmox config, first deployment
- [Local Network Setup](docs/network-setup.md) - DNS configuration, client setup, troubleshooting

## Prerequisites

- Terraform >= 1.0
- Ansible Core >= 2.14
- Docker >= 24.0
- Python >= 3.12
- Make
- OpenSSH (for ssh-cleanup and ssh-accept-keys)
