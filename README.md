# Homelab
<p align="left">
  <img src="https://img.shields.io/badge/Gitleaks-Protected-brightgreen?style=flat-square&logo=git" alt="Gitleaks" />
  <img src="https://img.shields.io/badge/Trivy-Scanned-blue?style=flat-square&logo=security" alt="Trivy" />
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square" alt="License" />
</p>

![Architecture Diagram](docs/images/diagram.png)

![Dell OptiPlex Homelab](docs/images/dell_optiplex.png)

Proxmox VE homelab managed with Terraform and Ansible. Single `make all` provisions infrastructure, configures hosts, and deploys apps.

## Quick Start

```bash
make setup                                          # mise toolchain + venv + config templates
# Edit terraform/terraform.tfvars with Proxmox credentials
# Edit ansible/group_vars/all/vault.yml with secrets
make all                                            # full deployment
```

`make setup` runs `make tools` (`mise install` for the versions pinned in [`.mise.toml`](.mise.toml)),
creates `ansible/.venv` (with `ansible-core`, `paramiko`, `proxmoxer`, `requests`) from the pinned
Python, installs collections, and copies `vault.yml` / `terraform.tfvars` from templates if missing.
Activate the venv with `source ansible/.venv/bin/activate` if you want to run `ansible-playbook`
directly.

## Commands

```bash
make help                # list all targets
make setup               # mise toolchain + venv + collections + config templates
make tools               # install the toolchain pinned in .mise.toml
make tf-init             # initialize Terraform
make tf-plan             # preview infrastructure
make tf-apply            # apply infrastructure
make tf-destroy          # destroy all infrastructure
make ansible-install     # install Ansible collections (uses .venv if present)
make ansible-all         # run all playbooks (adguard + docker + plex + k3s)
make ansible-adguard     # deploy AdGuard Home
make ansible-docker      # deploy Docker host
make ansible-plex        # deploy Plex Media Server
make ansible-k3s         # deploy K3s single-node (192.168.1.104)
make ansible-pve         # mount external USB disks on Proxmox
make ansible-dry-run     # check mode all playbooks
make ssh-cleanup         # remove stale SSH host keys (.100, .102, .104)
make ssh-accept-keys     # accept SSH host keys (.100, .102, .104)
make docker-context      # remote Docker context setup (DOCKER_USER ?= skoltun)
make kubectl-config      # wire ~/.kube/config from the fetched k3s.yaml (127.0.0.1 -> 192.168.1.104)
make helm-diff           # install the helm-diff plugin, verified against the cluster
make apps-diff           # show what would change for every release in apps/k3s/helmfile.yaml
make apps                # install/upgrade every release in apps/k3s/helmfile.yaml (idempotent)
make apps-list           # list the releases declared in apps/k3s/helmfile.yaml
make apps-destroy        # uninstall every release in apps/k3s/helmfile.yaml
make headlamp-token      # print a K3s dashboard login token
make monitoring-password # print the generated Grafana admin password
make clean               # remove venv
```

> `make all` runs `ansible-pve` → `tf-init` → `tf-apply` → `ansible-pve-host` → `ansible-all` (adguard + docker + plex + k3s). Manual `make ansible-*` runs also accept keys automatically (`ssh-accept-keys` covers .100, .102, .104). After K3s, run `make kubectl-config` to wire `~/.kube/config` and `make helm-diff` before `make apps`.

`kubectl`, `helm`, `helmfile`, `terraform` and `python` are not installed by the Makefile — they are
pinned in [`.mise.toml`](.mise.toml) and every target invokes them through `mise exec`, so the
versions in that file are the ones that run. See [Prerequisites](#prerequisites).

## Infrastructure

| Host | Type | IP | Purpose |
|------|------|----|---------|
| pve (Proxmox) | Host | 192.168.1.100 | Proxmox VE host (API + LXC transport) |
| adguard | LXC (Debian 13) | 192.168.1.101 | DNS ad blocking (AdGuard Home) |
| docker | VM (Ubuntu 24.04) | 192.168.1.102 | Container runtime (Docker + proxy-net) |
| plex | LXC (Debian 13) | 192.168.1.103 | Plex Media Server (media + config on USB SSD) |
| k3s | VM (Ubuntu 24.04) | 192.168.1.104 | K3s single-node (Traefik + Flannel, `terraform/modules/k3s_vm`) |
| gateway | Router | 192.168.1.1 | Network gateway |

Subnet: `192.168.1.0/24` · Tags: `management-plane` + `role-adguard`/`role-docker`/`role-plex`/`role-k3s`. See [Local Network Setup](docs/network-setup.md) for DHCP/DNS details. K3s kubeconfig is fetched to `ansible/playbooks/files/k3s.yaml` and wired locally via `make kubectl-config`.

## Apps

Two mechanisms, no others:

- **Docker Compose** on the Docker VM — add `apps/docker/<name>/docker-compose.yml`, attached to the
  external `proxy-net` bridge, routed by `VIRTUAL_HOST` under the `*.docker.internal` wildcard.
- **Helmfile** on K3s — add a release to `apps/k3s/helmfile.yaml` with overrides in
  `apps/k3s/<name>/values.yaml`, then `make apps`.

See [Apps](apps/README.md) for how to add, deploy, scope, and retire either kind.

## Documentation

- [Initial Setup](docs/setup.md) - Prerequisites, Proxmox config, first deployment, troubleshooting
- [Local Network Setup](docs/network-setup.md) - DNS configuration, client setup, trusting the AdGuard TLS certificate, troubleshooting
- [Ansible](ansible/README.md) - Playbooks, vault, TLS cert, Docker network
- [Apps](apps/README.md) - Adding and deploying apps with Docker Compose or helmfile

## Prerequisites

- [mise](https://mise.jdx.dev/getting-started.html) — the only tool you install yourself. It manages
  everything else from [`.mise.toml`](.mise.toml); `make tools` runs `mise install` for you.
- Proxmox VE host reachable at `192.168.1.100:8006`
- Make, OpenSSH, and Docker >= 24.0 (Docker is not managed by mise — it is the runtime on the
  Docker VM, not a local CLI dependency)
- Ansible Core >= 2.14 — installed into `ansible/.venv` by `make setup`, no global install needed

Pinned in [`.mise.toml`](.mise.toml) and installed by `make tools`:

| Tool | Version |
|------|---------|
| Python | 3.12 |
| Terraform | 1.16 |
| kubectl | 1.37.1 |
| Helm | 4.3.0 |
| helmfile | 1.8.0 |

`make kubectl-config` wires `~/.kube/config` and fails if the cluster is unreachable; `make helm-diff`
installs the mandatory `helm-diff` plugin and verifies cluster access. Neither needs sudo.

To use a different tool version, edit `.mise.toml` (or `mise use helm@3.22.0`) and re-run
`make tools`.

Versions tested: Terraform 1.16.x, kubectl `v1.37.1` against server `v1.36.4+k3s1`, Helm `v4.3.0`,
helmfile `1.8.0`, helm-diff `3.15.15`.

Provider/collections pinned: `bpg/proxmox 0.108.0` (`terraform/providers.tf:5`, `terraform/.terraform.lock.hcl:5`), `ansible.posix 2.2.0`, `community.docker 5.2.1`, `community.general 13.0.1`, `community.proxmox 2.0.0` (`ansible/requirements.yml:1`).
