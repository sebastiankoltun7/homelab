# Ansible Configuration

This directory contains the automation playbooks for configuring Proxmox-managed infrastructure.

See the [project README](../README.md) and [Initial Setup](../docs/setup.md) for full provisioning flow.

## Prerequisites

- **Python:** 3.12, pinned in [`.mise.toml`](../.mise.toml) and installed by `mise install`
- **Ansible Core:** 2.14 or higher, installed into `.venv` by `mise run setup-venv`
- **Environment:** WSL2 / Linux / macOS

## Quick Start

```bash
# From the project root
mise install          # install the pinned toolchain (Python, terraform, kubectl, helm, helmfile, bw)
mise run setup        # create .venv + install ansible-core + collections + vault + SSH key + HCP token
mise run ansible-install  # re-install collections (uses .venv if present)

# Activate venv for direct usage
source ansible/.venv/bin/activate

# Deploy services
mise run ansible-adguard  # AdGuard Home (LXC .101 via Proxmox API, Let's Encrypt wildcard cert)
mise run ansible-docker   # Docker host (192.168.1.102, user {{ admin_username }})
mise run ansible-plex     # Plex Media Server (LXC .103 via Proxmox API, external disks + GPU passthrough)
mise run ansible-k3s      # K3s single-node (192.168.1.104, user {{ admin_username }})
mise run ansible-all      # all (adguard + docker + plex + k3s, runs ssh-accept-keys first)
mise run ansible-dry-run  # check mode
# Local kubectl wiring:
mise run kubectl-config   # configure ~/.kube/config from ansible/playbooks/files/k3s.yaml
```

`mise run ansible-adguard`, `ansible-all` and `ansible-dry-run` read the Cloudflare API token from
Bitwarden (item `Cloudflare token (HomeLab)`) and pass it to the playbook, so the vault must be
unlocked — export `BW_SESSION` to skip the prompt.

`mise run ansible-*` tasks automatically run `ssh-accept-keys`, which covers `.100`, `.102`, `.104`.
`mise run all` also runs `ssh-cleanup` before ansible, and the K3s playbook may need
`mise run wait-for-vms` to have passed if the VM was just created.

## Vault (Secrets)

Secrets live in `group_vars/all/vault.yml` (gitignored via `../.gitignore:24`). On first run `mise run setup` copies the template for you.

```bash
# Manually create if needed
mise run vault-create

# Edit with your values
$EDITOR ansible/group_vars/all/vault.yml
```

Required variables:

| Variable | Description |
|---|---|
| `admin_username` | Admin username for VMs and AdGuard dashboard (must match `terraform.tfvars`) |
| `adguard_admin_password_hash` | bcrypt hash of the AdGuard Home admin password |

Generate a bcrypt hash:

```bash
htpasswd -bnBC 10 "" 'yourpassword' | tr -d ':\n' | sed 's/$2y/$2a/'
```

## Inventory

- `role_docker` → `docker-host` `192.168.1.102` via SSH as `{{ admin_username }}` (`group_vars/role_docker.yml:2`)
- `role_adguard` → `adguard-host` Proxmox host `192.168.1.100` via `community.proxmox.proxmox_pct_remote` (`inventory.yml:14`, `proxmox_vmid: 101`)
- `role_plex` → `plex-host` Proxmox host `192.168.1.100` via `community.proxmox.proxmox_pct_remote` (`inventory.yml:14`, `proxmox_vmid: 103`)
- `role_k3s` → `k3s-node` `192.168.1.104` via SSH as `{{ admin_username }}` (`inventory.yml:35`, `group_vars/role_k3s.yml:1`)

The AdGuard/Plex LXC containers are not SSHed directly; Ansible tunnels via Proxmox. K3s is a VM reached directly over SSH.

`playbooks/install_plex.yml` additionally targets the `pve` group (`192.168.1.100` over SSH) because
LXC bind mounts and device passthrough can only be applied by `root@pam` itself. It handles the
external disks, the `/PlexMedia` + `/plex-config` bind mounts, and the `/dev/dri` GPU entries, so
there is no separate Proxmox-host playbook.

## AdGuard Home TLS

AdGuard Home runs with TLS enabled (`https://adguard.skoltun.dev`, `playbooks/adguard/AdGuardHome.yml.j2:4`) using a **real Let's Encrypt wildcard certificate**, not a self-signed one. `playbooks/install_adguard.yml` does, on the first run:

1. Installs `certbot` + `python3-certbot-dns-cloudflare` (`playbooks/install_adguard.yml:43`).
2. Writes the Cloudflare API token to `/opt/AdGuardHome/cloudflare.ini`, mode `0600`
   (`playbooks/install_adguard.yml:51`). The token arrives as the `cloudflare_api_token` extra var,
   which `mise run ansible-adguard` / `ansible-all` / `ansible-dry-run` fetch from Bitwarden — running
   the playbook by hand requires passing it yourself:
   `-e cloudflare_api_token=<token>`.
3. Requests a wildcard certificate for `skoltun.dev` + `*.skoltun.dev` via DNS-01
   (`playbooks/install_adguard.yml:62`), skipped when
   `/etc/letsencrypt/live/skoltun.dev/fullchain.pem` already exists. DNS-01 needs no inbound port and
   no public DNS record for the container.
4. Copies `fullchain.pem` → `{{ adguard_cert_directory }}/cert.crt` and `privkey.pem` →
   `{{ adguard_cert_directory }}/private.key` (mode `0600`), which is what `AdGuardHome.yml.j2`
   points at.

Because the certificate is publicly trusted, nothing has to be installed on client machines and
`https://adguard.skoltun.dev` works without a browser warning. The dashboard stays reachable over
plain HTTP too (`force_https: false`). The cert covers the hostname only, not `192.168.1.101`, so
use the hostname unless you add an IP SAN.

The domain and certificate directory are set via `adguard_tls_server_name` and
`adguard_cert_directory` in `group_vars/role_adguard.yml:5`.

To **renew** the certificate, certbot's own renewal timer does it (installed by the `certbot`
package), but AdGuard serves the *copied* files in `adguard_cert_directory` — nothing re-copies them
automatically, so re-run `mise run ansible-adguard` after a renewal to refresh the chain. For a
forced re-issue, delete `/etc/letsencrypt/live/skoltun.dev/` on the container first, then re-run the
task.

If you do not have a Cloudflare token (or do not own the domain yet), run the playbook with a
self-signed certificate instead — see the git history for the OpenSSL-based version.

## Docker Network & Host

The Docker playbook (`playbooks/install_docker.yml:58`) creates a shared bridge network (`proxy-net`) used by nginx and application containers. Containers attached to this network can reach each other by container name, enabling service discovery without exposing ports on the host.

Host config: data disk `virtio-DOCKER-DATA` mounted at `/mnt/docker-data` (`group_vars/role_docker.yml:5`), Docker `data-root` and `containerd` root on that mount, weekly prune cron Sunday 01:00 (`group_vars/role_docker.yml:22`, `tasks/docker_cleanup_cron.yml:14`), `geerlingguy.docker` role for engine + compose plugin.

## Plex Media Server

`playbooks/install_plex.yml` has two plays. The first targets the `pve` group and prepares the host:

1. Mounts every entry of `external_disks` (`group_vars/pve.yml`) by UUID under `/mnt/pve/<name>` via
   `tasks/configure_external_disk.yml`, asserting `assert_dirs` and creating `create_dirs`.
2. Adds the `/PlexMedia` and `/plex-config` bind mounts to `/etc/pve/lxc/<vmid>.conf` with `pct set`.
3. Adds `/dev/dri` passthrough lines (`lxc.cgroup2.devices.allow`, `lxc.mount.entry`) and chmods the
   devices to `0666`, dropping a stale `card0` entry.

The second play targets `role_plex` and installs `plexmediaserver` from the Plex apt repo, pointing
`PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR` at `/plex-config` through a systemd drop-in.

## K3s & kubeconfig

Terraform (`terraform/modules/k3s_vm`) creates the single-node control-plane VM `192.168.1.104`
(`inventory.yml:35` `role_k3s`); `playbooks/install_k3s.yml` then configures it:

1. Loads `br_netfilter` + `overlay` and sets the bridge/IP-forward sysctls.
2. Formats the second disk `/dev/vdb` as ext4 and mounts it at `/mnt/k3s-data`.
3. Checks `/usr/local/bin/k3s`; if absent runs `curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-ip=192.168.1.104 --data-dir=/mnt/k3s-data --write-kubeconfig-mode 644" sh -` (`playbooks/install_k3s.yml:56`).
4. Ensures the `k3s` systemd service is started/enabled and `k3s.yaml` is mode `0644`, then `fetch`es
   `/etc/rancher/k3s/k3s.yaml` to `playbooks/files/k3s.yaml` (`playbooks/install_k3s.yml:77`, flat).
5. That fetched file is gitignored via `.gitignore:36` (`/ansible/playbooks/files/`) and contains `server: https://127.0.0.1:6443` — patch it before use.

Local wiring:

```bash
mise run kubectl-config   # patch 127.0.0.1 -> 192.168.1.104, cp -> ~/.kube/config, chmod 600, verify
kubectl get nodes     # ubuntu Ready control-plane v1.36.4+k3s1
kubectl cluster-info && kubectl get pods -A
```

`kubectl` is pinned in [`.mise.toml`](../.mise.toml), so the task needs no PATH setup and no sudo.
In a shell that has not run `mise activate`, call it as `mise exec -- kubectl get nodes`.

Pinned collections: see `requirements.yml` — `ansible.posix 2.2.0`, `community.docker 5.2.1`, `community.general 13.0.1`, `community.proxmox 2.0.0`. The K3s firewall is in `terraform/modules/k3s_vm` (ingress 6443/10250/8472/80/443, DNS egress to `192.168.1.101`).
