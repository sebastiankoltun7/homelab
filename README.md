# Homelab

A fully automated Proxmox VE homelab managed with Infrastructure-as-Code. 
From a single `make all` command, this repository provisions VMs and LXC containers via Terraform, 
configures them with Ansible, and deploys containerized applications via Docker -- all driven from a local development machine.

## Overview

This homelab follows a layered deployment pipeline where each tool owns a clear responsibility:

```
┌─────────────┐     ┌─────────┐     ┌──────────────────┐
│  Terraform   │────▶│ Ansible │────▶│  Docker / Apps   │
│  (Provision) │     │ (Config)│     │  (Deploy)        │
└─────────────┘     └─────────┘     └──────────────────┘
```

**Infrastructure managed today:**

| Resource | Type | IP | Purpose |
|----------|------|----|---------|
| AdGuard Home | LXC (Debian 13) | 192.168.1.101 | DNS-level ad blocking |
| Docker Host | VM (Ubuntu 24.04) | 192.168.1.102 | Container runtime for applications |

Both resources run on a single Proxmox node (`pve` at `192.168.1.100`).

## Architecture

### Terraform Modules

Infrastructure is defined through a **two-tier module hierarchy** that separates generic Proxmox resource creation from role-specific defaults:

```
Root (main.tf)
├── adguard_home  →  modules/adguard_lxc  →  modules/proxmox_lxc  (base LXC)
└── docker        →  modules/docker_vm    →  modules/proxmox_vm   (base VM)
```

**Base modules** (`proxmox_vm`, `proxmox_lxc`) handle raw resource creation -- downloading OS images, cloud-init configuration, networking, and disk setup. **Composite modules** (`docker_vm`, `adguard_lxc`) wrap the base modules with role-specific defaults like resource sizes, disk layouts, and tags.

This means adding a new service is a matter of creating a thin composite module with a few variable overrides -- no need to repeat infrastructure boilerplate.

### Docker Host Strategy

The Docker VM uses a **two-disk architecture**:

- **Boot disk** (10 GB, `OS-BOOT`) -- Ubuntu OS and system packages
- **Data disk** (50 GB, `DOCKER-DATA`) -- Docker engine root, containerd, and all container data

The data disk is mounted by persistent device ID (`/dev/disk/by-id/virtio-DOCKER-DATA`) so it survives device reordering. Ansible formats and mounts this disk, then configures Docker to use it as the data root. Container data is completely isolated from the OS, making backups, resizing, and recovery straightforward.

### Application Deployment via Docker Context

The Docker host is configured as a **remote Docker context**, allowing direct deployment from a local machine:

```bash
# One-time setup (uses DOCKER_USER and DOCKER_HOST_IP from Makefile)
make docker-context

# Deploy -- runs on the remote host, no local Docker daemon needed
docker compose up -d
```

This means application stacks in `apps/docker/` can be deployed to the homelab without SSH-ing into the host or running anything locally beyond the Docker CLI.

### LXC Management via Proxmox pct

AdGuard runs in an unprivileged LXC container. Instead of configuring SSH inside the container, Ansible connects through the Proxmox host using `community.proxmox.proxmox_pct_remote` and executes commands via `pct exec`:

```yaml
ansible_connection: community.proxmox.proxmox_pct_remote
ansible_host: 192.168.1.100  # Proxmox host
proxmox_vmid: 101             # LXC container ID
```

This is the standard pattern for managing Proxmox containers with Ansible -- it avoids container-level SSH configuration entirely.

## Good Practices

### Infrastructure as Code
- **Two-tier Terraform modules** -- base modules for generic resources, composite modules for role-specific defaults. Adding new infrastructure is a one-file exercise.
- **Extensive input validation** -- IP format, ID ranges, memory minimums, disk counts, SSH key format, and image URLs are all validated at plan time.
- **Lifecycle `ignore_changes`** -- cloud-init and agent blocks are marked as post-creation drift-safe, preventing Terraform from overwriting changes made after initial provisioning.
- **Cloud-init templating** -- user data is rendered from a `.tftpl` file with proper user setup, SSH key injection, and guest agent enablement.
- **Terraform Cloud state backend** -- remote state with locking and versioning, no self-hosted backend to maintain.

### Configuration Management
- **Idempotent playbooks** -- AdGuard install uses `creates:` to skip reinstallation, Docker disk formatting uses `force: false`.
- **Separation of concerns** -- group variables hold all configurable values; playbooks contain only logic.
- **Reusable task files** -- Docker cleanup cron is extracted into `tasks/docker_cleanup_cron.yml` for composability.
- **Disk-by-id device paths** -- `/dev/disk/by-id/virtio-DOCKER-DATA` instead of `/dev/vdb` avoids device reordering issues across reboots.

### Security
- **Secrets never committed** -- `.gitignore` excludes `*.tfvars`, `.env`, vault files, and credential files. A `.tfvars.template` provides a safe starting point.
- **Sensitive variables marked** -- Terraform variables containing credentials are marked `sensitive = true`.
- **SSH key-based authentication** -- no passwords in playbooks or cloud-init. Password login is locked.
- **Unprivileged containers** -- AdGuard LXC runs unprivileged with only necessary capabilities.
- **Log rotation** -- Docker daemon configured with `max-size: 10m` and `max-file: 3` to prevent disk exhaustion from container logs.
- **Automated cleanup** -- Weekly `docker system prune` cron job prevents image and volume accumulation.

### Operational Excellence
- **Makefile interface** -- self-documenting `make` targets abstract all tool-specific commands. `make help` lists everything.
- **Dry-run support** -- `make ansible-dry-run` runs all playbooks in check mode before applying changes.
- **Full pipeline** -- `make all` orchestrates the complete flow: Terraform init, apply, Ansible collections install, and all playbooks in dependency order (DNS before Docker).
- **Tagging strategy** -- Proxmox resources tagged with role and `management-plane` for filtering and visibility.

## Repository Structure

```
homelab/
├── ansible/
│   ├── ansible.cfg                  # Ansible configuration
│   ├── group_vars/
│   │   └── role_docker.yml          # Docker host variables
│   ├── inventory.yml                # Host inventory
│   ├── playbooks/
│   │   ├── install_adguard.yml      # AdGuard Home installation
│   │   └── install_docker.yml       # Docker engine setup
│   ├── requirements.yml             # Ansible collection dependencies
│   └── tasks/
│       └── docker_cleanup_cron.yml  # Reusable cleanup task
├── apps/
│   └── docker/
│       └── mini_io/.env             # MinIO credentials
├── terraform/
│   ├── main.tf                      # Root module definitions
│   ├── providers.tf                 # Proxmox provider + Terraform Cloud backend
│   ├── variables.tf                 # Input variables
│   ├── terraform.tfvars.template    # Credential template
│   └── modules/
│       ├── proxmox_lxc/             # Base LXC container module
│       │   ├── main.tf
│       │   └── variables.tf
│       ├── proxmox_vm/              # Base VM module
│       │   ├── main.tf
│       │   ├── cloud-init.tftpl
│       │   ├── outputs.tf
│       │   └── variables.tf
│       ├── adguard_lxc/             # AdGuard Home LXC (composite)
│       │   └── main.tf
│       └── docker_vm/               # Docker host VM (composite)
│           └── main.tf
└── Makefile                         # Setup and common commands
```

## Quick Start

```bash
# 1. Clone the repository
git clone <repository-url> homelab
cd homelab

# 2. Run automated setup (creates venv, installs dependencies)
make setup

# 3. Configure credentials
cp terraform/terraform.tfvars.template terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your Proxmox credentials

# 4. Deploy everything
make all
```

## Usage

### Terraform

```bash
make tf-init      # Initialize providers and modules
make tf-plan      # Preview infrastructure changes
make tf-apply     # Apply infrastructure changes
make tf-destroy   # Destroy all managed infrastructure
```

### Ansible

```bash
make ansible-install   # Install Ansible collection dependencies
make ansible-all       # Run all playbooks (AdGuard + Docker)
make ansible-docker    # Deploy Docker host only
make ansible-adguard   # Deploy AdGuard Home only
make ansible-dry-run   # Dry-run all playbooks (check mode)
```

### Combined

```bash
make all    # Full pipeline: Terraform + Ansible
make clean  # Remove Python virtual environment
make help   # List all available targets
```

### Deploying Applications

```bash
# One-time: set up Docker context
make docker-context

# Deploy from apps/docker/<app>/
cd apps/docker/mini_io
docker compose up -d
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Terraform](https://www.terraform.io/) | >= 1.0 | Infrastructure provisioning |
| [Ansible](https://www.ansible.com/) | >= 2.21 | Configuration management |
| [Docker](https://www.docker.com/) | >= 24.0 | Application deployment |
| [Python](https://www.python.org/) | >= 3.12 | Ansible runtime |
| [Make](https://www.gnu.org/software/make/) | any | Task automation |

### Ansible Collections

| Collection | Version | Purpose |
|------------|---------|---------|
| `ansible.posix` | 2.2.0 | POSIX system modules |
| `community.general` | 13.0.1 | General-purpose modules |
| `community.proxmox` | 2.0.0 | Proxmox LXC management via pct |
