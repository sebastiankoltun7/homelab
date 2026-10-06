# Ansible Configuration

Automation playbooks and roles for Proxmox-managed homelab infrastructure.

## Prerequisites
- Python 3.12 & Ansible Core 2.14+
- Collections pinned in requirements.yml

## Running
    ansible-playbook site.yml                    # Run all roles/plays
    ansible-playbook site.yml --limit role_adguard # Run a specific play
    ansible-playbook site.yml --check            # Dry run

## Playbooks & Targets (site.yml)
| Limit Flag | Target | Description |
| --- | --- | --- |
| role_adguard | AdGuard LXC (.101) | Installs & configures AdGuard Home |
| role_docker | Docker VM (.102) | Data disk, Docker engine, proxy-net bridge |
| pve,role_plex | Proxmox + Plex (.103) | Host storage/binds, then Plex container |
| role_k3s | K3s VM (.104) | Network prep, disk, K3s server, fetch kubeconfig |

## Inventory Structure
- LXC Containers: role_adguard, role_plex (reached via Proxmox host connection plugin).
- VMs: role_docker, role_k3s (reached via direct SSH).
- Proxmox Host: pve (handles LXC bind mounts).

## Roles & Variables
- Roles: adguard, docker, k3s, plex (modular tasks + handlers). External role: geerlingguy.docker.
- Vault: Secrets in group_vars/all/vault.yml (copy from vault.yml.template).

## Collections
Pinned in requirements.yml: ansible.posix, community.docker, community.general, community.proxmox.