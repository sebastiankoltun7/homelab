# Ansible Configuration

This directory contains the automation playbooks for configuring Proxmox-managed infrastructure.

See the [project README](../README.md) and [Initial Setup](../docs/setup.md) for how the playbooks
fit into the provisioning flow.

## Prerequisites

- **Python:** 3.12
- **Ansible Core:** 2.14 or higher, together with the collections pinned in `requirements.yml`
- **Environment:** WSL2 / Linux / macOS

## Running

```bash
# From this directory, in an environment that has ansible-core and the collections
ansible-playbook playbooks/site.yml            # all playbooks
ansible-playbook playbooks/install_adguard.yml # a single playbook
ansible-playbook playbooks/site.yml --check    # dry run
```

`ansible.cfg` points at the inventory in this directory and disables host key checking. The
project keeps its Python dependencies in a virtualenv here — activate it (or install `ansible-core`
plus `ansible-galaxy install -r requirements.yml` yourself) before running anything.

## Playbooks

| Playbook | Target | What it does |
| --- | --- | --- |
| `site.yml` | all of the below | imports every playbook in provisioning order |
| `install_adguard.yml` | AdGuard LXC `.101` | installs AdGuard Home, renders its config, starts the service |
| `install_docker.yml` | Docker VM `.102` | data disk, Docker engine + compose plugin, `proxy-net` bridge, prune cron |
| `install_plex.yml` | Proxmox host + Plex LXC `.103` | host-side disks/binds/GPU, then installs Plex inside the container |
| `install_k3s.yml` | K3s VM `.104` | kernel/network prep, data disk, K3s server, fetches the kubeconfig |

## Inventory

- **AdGuard** (`role_adguard`) and **Plex** (`role_plex`) are LXC containers. They are not SSHed
  directly — Ansible reaches them through the Proxmox host with the remote container connection
  plugin, addressing them by VMID.
- **Docker** (`role_docker`) and **K3s** (`role_k3s`) are VMs reached directly over SSH as the admin
  user from the vault.
- A separate **`pve`** group targets the Proxmox host itself over SSH, because LXC bind mounts and
  device passthrough can only be applied by `root@pam`.

## Roles

There are no custom roles: shared logic lives in task files that playbooks include where needed
(external disk preparation, Docker cleanup cron). The one external role,
`geerlingguy.docker`, is pinned in `requirements.yml` and used by the Docker playbook to install the
engine and the compose plugin.

## Variables

Group variables are split by scope:

- **`all`** — the admin username and the vault (secrets).
- **`pve`** — external drives attached to the Proxmox host (by-id name, required and created
  directories, mount options).
- **`role_adguard` / `role_docker` / `role_k3s` / `role_plex`** — per-service settings such as DNS
  rewrites, disk paths and mount points.

### Vault (Secrets)

Secrets live in `group_vars/all/vault.yml` (gitignored). A tracked template is copied there on
first setup — see the project README.

| Variable | Description |
|---|---|
| `admin_username` | Admin username for VMs and the AdGuard dashboard (must match `terraform.tfvars`) |
| `adguard_admin_password_hash` | bcrypt hash of the AdGuard Home admin password |

Generate a bcrypt hash:

```bash
htpasswd -bnBC 10 "" 'yourpassword' | tr -d ':\n' | sed 's/$2y/$2a/'
```

## AdGuard Home

The AdGuard playbook installs AdGuard Home on the LXC container, renders its configuration, and
starts the service. The dashboard listens on plain HTTP — certificates are handled once for the
whole lab instead (see [Apps](../apps/README.md#tls-for-the-ingresses)).

Configuration highlights, all driven from group variables:

- **DNS rewrites** map the lab's hostnames: `adguard.homelab` and `plex.homelab` to their
  containers, plus the `*.docker.skoltun.dev` and `*.k3s.skoltun.dev` wildcards to the Docker and
  K3s hosts. Clients using AdGuard as their resolver therefore need no manual DNS entries.
- **Admin credentials** come from the vault: the username follows `admin_username`, the password is
  a bcrypt hash.
- IPv6 resolution and the dashboard theme are toggled the same way.

The configuration is rendered on every run, so changes take effect on the next playbook run (the
service restarts through a handler).

## Docker Network & Host

The Docker playbook creates a shared bridge network (`proxy-net`) used by the reverse proxy and
application containers. Containers attached to this network can reach each other by container name,
enabling service discovery without exposing ports on the host.

Host config: the second disk is formatted and mounted as the Docker data area, Docker's `data-root`
and containerd root live on that mount, a weekly prune runs Sunday 01:00, and the engine plus
compose plugin come from `geerlingguy.docker`.

## Plex Media Server

The Plex playbook has two plays. The first targets the Proxmox host and:

1. Mounts every configured external disk by UUID under `/mnt/pve/<name>`, asserting the directories
   that must already exist and creating the ones marked for creation.
2. Binds the media and config directories into the Plex container.
3. Adds the GPU passthrough entries to the container config and makes the devices accessible,
   dropping a stale entry if one is left over.

The second play installs `plexmediaserver` from the Plex apt repo and points its application-support
directory at the config bind mount through a systemd override.

## K3s & kubeconfig

Terraform creates the single-node control-plane VM `192.168.1.104`; the K3s playbook then
configures it:

1. Loads the kernel modules and sysctls Kubernetes networking needs.
2. Formats the second disk and mounts it as the K3s data directory.
3. Installs the K3s server (if absent) with the node IP, the data directory and a world-readable
   kubeconfig.
4. Ensures the service is running and fetches the kubeconfig to a local, gitignored file — it points
   at loopback by default, so patch the server address before using it with `kubectl`.

## Collections

Pinned in `requirements.yml`: `ansible.posix 2.2.0`, `community.docker 5.2.1`,
`community.general 13.0.1`, `community.proxmox 2.0.0`, plus the `geerlingguy.docker` role. K3s
firewall rules (API, kubelet, Flannel, ingress ports, DNS egress to AdGuard) are declared with the
rest of the infrastructure, not here.
