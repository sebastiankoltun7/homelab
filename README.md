# Homelab
<p>
  <img src="https://img.shields.io/badge/Gitleaks-Protected-brightgreen?style=flat-square&logo=git" alt="Gitleaks" />
  <img src="https://img.shields.io/badge/Trivy-Scanned-blue?style=flat-square&logo=security" alt="Trivy" />
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square" alt="License" />
</p>

![Architecture Diagram](docs/images/diagram.png)

![Dell OptiPlex Homelab](docs/images/dell_optiplex.png)

Proxmox VE homelab managed with Terraform and Ansible, driven by
[mise](https://mise.jdx.dev). A single `mise run all` provisions infrastructure, configures hosts,
and deploys apps.

## Quick Start

```bash
# 1. Install mise once
curl https://mise.run | sh

# 2. Install the pinned toolchain (Python, Terraform, kubectl, Helm, helmfile, Bitwarden CLI)
mise install

# 3. Full deployment
mise run all
```

`mise run all` is the whole deployment, from empty disks to deployed apps. It is safe to re-run —
every step is idempotent — but for day-to-day work prefer the individual tasks below.

Before step 3 you need two config files. `mise run setup` creates them from templates, imports your
SSH key and the HCP Terraform token from Bitwarden, and installs the local Docker client:

```bash
mise run setup
$EDITOR terraform/terraform.tfvars       # Proxmox credentials
$EDITOR ansible/group_vars/all/vault.yml # secrets, admin_username must match tfvars
```

Then `mise run all`, and finally the service logins:

```bash
mise run headlamp-token        # Headlamp  (Kubernetes dashboard)
mise run monitoring-password   # Grafana   (monitoring stack)
```

## Tasks

Every task is declared in `.mise.toml` and runs from the repo root. `mise run <task>` lists them
with their descriptions; `mise <task>` is shorthand for the same thing.

```bash
mise run all                  # full deployment: disks, Terraform, Ansible, local tools, k3s apps
```

### Setup

```bash
mise run setup                # full local bootstrap (toolchain, Docker, SSH key, HCP token, venv, collections, templates)
mise run tools                # mise install + print the resolved version of each tool
mise run install-docker-local # install Docker Engine locally (Linux/WSL2)
mise run ssh-key              # fetch the homelab SSH key from Bitwarden, load it into ssh-agent
mise run terraform-auth       # fetch the HCP Terraform token from Bitwarden -> ~/.terraform.d
mise run setup-venv           # create ansible/.venv from the pinned Python + dependencies
mise run ansible-install      # install Ansible collections (re-runs when requirements.yml changes)
mise run vault-create         # copy vault.yml.template -> group_vars/all/vault.yml (skip if exists)
mise run terraform-tfvars     # copy terraform.tfvars.template -> terraform.tfvars (skip if exists)
```

### Terraform

```bash
mise run tf-init              # initialize Terraform
mise run tf-plan              # preview infrastructure
mise run tf-apply             # apply infrastructure
mise run tf-destroy           # destroy all infrastructure
```

### Ansible

```bash
mise run ansible-all          # all playbooks (adguard + docker + plex + k3s)
mise run ansible-adguard      # deploy AdGuard Home (DNS, rewrites, admin dashboard)
mise run ansible-docker       # deploy Docker host
mise run ansible-plex         # deploy Plex Media Server (external disks, bind mounts, GPU passthrough)
mise run ansible-k3s          # deploy K3s single-node (192.168.1.104)
mise run ansible-dry-run      # check mode, all playbooks
```

### Local machine

```bash
mise run wait-for-vms         # wait for the Docker/K3s VMs to finish booting and cloud-init
mise run ssh-cleanup          # remove stale SSH host keys (.100, .102, .104)
mise run ssh-accept-keys      # accept SSH host keys (.100, .102, .104)
mise run docker-context       # remote Docker context "homelab" (DOCKER_USER from .mise.toml)
mise run kubectl-config       # wire ~/.kube/config from the fetched k3s.yaml (127.0.0.1 -> 192.168.1.104)
mise run helm-diff            # install the helm-diff plugin, verified against the cluster
mise run clean                # remove ansible/.venv and the dependency stamp
```

### K3s apps

```bash
mise run apps-diff            # show what would change for every release in apps/k3s/helmfile.yaml
mise run apps                 # install/upgrade every release in apps/k3s/helmfile.yaml (idempotent)
mise run apps-list            # list the releases declared in apps/k3s/helmfile.yaml
mise run apps-destroy         # uninstall every release in apps/k3s/helmfile.yaml
```

`mise run apps` also stores the Cloudflare API token in the `cert-manager` namespace, then applies
the ClusterIssuer and the cluster-wide wildcard certificate that every K3s ingress serves with.
See [Apps](apps/README.md#tls-for-the-ingresses).

### Raspberry Pi

```bash
mise run bake-image           # download Raspberry Pi OS Lite and prebake it with cloud-init + the Bitwarden SSH key
```

See [scripts/raspberry](scripts/raspberry/README.md). The Pi is standalone — not managed by Terraform
or Ansible.

### Service logins

Credentials are not stored in the repo — read them out of the cluster:

```bash
mise run headlamp-token       # Headlamp login token, valid 24h
mise run monitoring-password  # generated Grafana admin password
```

| Service | URL | Login |
|---------|-----|-------|
| Headlamp | `https://dashboard.k3s.skoltun.dev` | paste the `headlamp-token` output |
| Grafana | `https://grafana.k3s.skoltun.dev` | user `admin`, password from `monitoring-password` |
| Prometheus | `https://grafana-prometheus.k3s.skoltun.dev` | none |
| AdGuard Home | `http://192.168.1.101` | `admin_username` + password from `vault.yml` |
| Plex | `http://192.168.1.103:32400/web` | claim once, then your Plex account |

Headlamp and Grafana are served with the cluster's Let's Encrypt wildcard certificate, so those URLs
are warning-free. AdGuard's dashboard is plain HTTP. Prometheus has no TLS configured, so it falls
back to Traefik's self-signed default and the browser asks you to accept the warning once.

`mise run all` ends with `mise run apps`, which prints the first three URLs together with the tasks
that produce the credentials.

> `mise run all` runs, in order: `ansible-install` → `ssh-cleanup` → `ssh-accept-keys` →
> `terraform-auth` → `tf-init` → `tf-apply` → `wait-for-vms` → `ansible-all` →
> `docker-context` → `kubectl-config` → `helm-diff` → `apps`. The individual `mise run ansible-*`
> deployment tasks accept host keys first (`ssh-accept-keys` covers .100, .102, .104); `ssh-cleanup`
> only happens inside `all`, so run it by hand after a VM rebuild.

`kubectl`, `helm`, `helmfile`, `terraform` and `python` are not installed globally — they are pinned
in `.mise.toml`, and mise tasks always run with those versions in `PATH`, even in a shell where
`mise activate` never ran. For one-off commands outside a task use `mise exec -- ...`.
See [Prerequisites](#prerequisites).

## Infrastructure

| Host | Type | IP | Purpose |
|------|------|----|---------|
| pve (Proxmox) | Host | 192.168.1.100 | Proxmox VE host (API + LXC transport) |
| adguard | LXC (Debian 13) | 192.168.1.101 | DNS ad blocking (AdGuard Home) |
| docker | VM (Ubuntu 24.04) | 192.168.1.102 | Container runtime (Docker + proxy-net) |
| plex | LXC (Debian 13) | 192.168.1.103 | Plex Media Server (media + config on USB SSD) |
| k3s | VM (Ubuntu 24.04) | 192.168.1.104 | K3s single-node (Traefik + Flannel) |
| gateway | Router | 192.168.1.1 | Network gateway |

Subnet: `192.168.1.0/24` · Every guest carries a `role-*` tag plus a plane tag — `management-plane`
for AdGuard and Docker, `media-plane` for Plex, `k3s-node` for K3s. See
[Local Network Setup](docs/network-setup.md) for DHCP/DNS details. The K3s kubeconfig is fetched by
the K3s playbook and wired locally via `mise run kubectl-config`.

## Apps

Two mechanisms, no others:

- **Docker Compose** on the Docker VM — add `apps/docker/<name>/docker-compose.yml`, attached to the
  external `proxy-net` bridge, routed by `VIRTUAL_HOST` under the `*.docker.skoltun.dev` wildcard.
- **Helmfile** on K3s — add a release to `apps/k3s/helmfile.yaml` with overrides in
  `apps/k3s/<name>/values.yaml`, then `mise run apps`.

See [Apps](apps/README.md) for how to add, deploy, scope, and retire either kind.

## Documentation

- [Initial Setup](docs/setup.md) - Prerequisites, Proxmox config, first deployment, troubleshooting
- [Local Network Setup](docs/network-setup.md) - Network map, DHCP reservations, client DNS
- [Ansible](ansible/README.md) - Playbooks, inventory, variables and vault
- [Apps](apps/README.md) - Adding and deploying apps with Docker Compose or helmfile
- [Raspberry Pi image baker](scripts/raspberry/README.md) - Prebaking Raspberry Pi OS with cloud-init

## Prerequisites

- [mise](https://mise.jdx.dev/getting-started.html) — the only tool you install yourself. It manages
  everything else from `.mise.toml`; `mise install` fetches the pinned versions.
- Bitwarden CLI + an unlocked vault — the tasks read three items from it: `homelab-ssh-key`
  (written to `~/.ssh/id_ed25519`), `hcp-terraform-token` (its notes become the HCP API token) and
  `Cloudflare token (HomeLab)` (its password becomes the Let's Encrypt DNS-01 token cert-manager
  uses for the cluster's wildcard certificate). Set `BW_SESSION` to skip the interactive unlock, and
  note that `terraform-auth` is interactive.
- A domain you control — `skoltun.dev` in this repo, delegated to Cloudflare, with an API token that
  can edit DNS for the zone. Every HTTPS endpoint gets a publicly trusted certificate, so there is
  nothing to trust manually. See [Initial Setup](docs/setup.md#5-domain-and-certificates).
- `jq` and OpenSSH — used by the `ssh-key` task and for SSH access to the hosts.
- Proxmox VE host reachable at `192.168.1.100:8006`
- Docker >= 24.0 — installed for you on Linux/WSL2 by `mise run install-docker-local`; the Docker VM
  is the runtime, so this is only the local client plus the remote `homelab` context.
- Ansible Core >= 2.14 — installed into `ansible/.venv` by `mise run setup-venv`, no global install
  needed. Activate it with `source ansible/.venv/bin/activate` to run `ansible-playbook` directly.
- `sudo` + `losetup` — only if you run `mise run bake-image` for the Raspberry Pi.

Pinned in `.mise.toml` and installed by `mise install`:

| Tool | Version |
|------|---------|
| Python | 3.12 |
| Terraform | 1.16 |
| kubectl | 1.37.1 |
| Helm | 4.3.0 |
| helmfile | 1.8.0 |
| Bitwarden CLI | latest |

`mise run kubectl-config` wires `~/.kube/config` and fails if the cluster is unreachable; `mise run
helm-diff` installs the mandatory `helm-diff` plugin from its release tarball and verifies cluster
access. Neither needs sudo.

To use a different tool version, edit `.mise.toml` (or `mise use helm@3.22.0`) and re-run
`mise install`.
