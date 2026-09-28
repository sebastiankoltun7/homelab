# Initial Setup Guide

Step-by-step setup for the homelab from scratch. For deploying apps, see [Apps](../apps/README.md).

## Prerequisites

Most tools install through the Makefile. Each target that writes to `/usr/local/bin` prompts for
sudo, so run them from a terminal.

| Tool | Make target | Manual alternative |
| --- | --- | --- |
| Terraform | — | `brew install terraform`, apt, `choco install terraform` |
| Ansible | `make setup` (creates `ansible/.venv`) | `pip install ansible-core` |
| Docker | — | `brew install --cask docker`, `apt install docker.io` |
| Python 3.12+ | `make setup` | `brew install python@3.12` |
| Make, OpenSSH | — | preinstalled on macOS/Linux |
| kubectl | `make kubectl-setup` | `brew install kubectl` |
| Helm | `make helm-setup` | `brew install helm` |
| helmfile + helm-diff | `make helmfile-setup` | `brew install helmfile` |

`make kubectl-setup` also copies the kubeconfig into `~/.kube/config`; `make helm-setup` and
`make helmfile-setup` verify cluster access and fail if the cluster is unreachable.

`make helmfile-setup` installs the mandatory `helm-diff` plugin from a release tarball, verified
against `keys/helm-diff.gpg` committed in this repo. Helm 4 requires that: it refuses plugins
installed from a git URL, and refuses tarballs whose signing key is not in a keyring.

Tested versions: Terraform 1.16.x, kubectl `v1.37.1` against server `v1.36.4+k3s1`, Helm `v4.3.0`,
helmfile `1.8.0`, helm-diff `3.15.15`.

> **Helm 4 vs 3:** Helm 4 defaults to server-side apply for *new* releases and renames
> `--atomic` → `--rollback-on-failure` and `--force` → `--force-replace`. Releases created by
> Helm 3 keep client-side apply after an upgrade. If a chart misbehaves, pin with
> `make helm-install HELM_VERSION=v3.22.0`.

## Proxmox Setup

### 1. Enable API Token Authentication

1. Log in to the Proxmox web UI
2. **Datacenter** > **Permissions** > **API Tokens** > **Add**
3. Select (or create) a user — never `root@pam`
4. Check **Privilege Separation: No**, so the token inherits the user's ACLs
5. Note the **Token ID** and **Token Secret**

### 2. Add your SSH key to the Proxmox host

Terraform and Ansible both reach the host over SSH:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""    # if you do not have one
ssh-copy-id root@192.168.1.100
ssh root@192.168.1.100                              # should not prompt
```

## Configuration

### 1. Run setup

```bash
make setup
```

Creates `ansible/.venv` with the Python dependencies, installs the pinned collections
(`make ansible-install`), and copies config templates if missing: `terraform/terraform.tfvars` and
`ansible/group_vars/all/vault.yml`. Activate the venv to run `ansible-playbook` directly:

```bash
source ansible/.venv/bin/activate
```

### 2. Configure Terraform

Edit `terraform/terraform.tfvars`. State goes to Terraform Cloud by default (`cloud` block in
`terraform/providers.tf`); remove that block to use local state instead.

| Field | Description |
|-------|-------------|
| `proxmox.ip` / `proxmox.port` | Proxmox host and API port |
| `proxmox.username` | API token as `user@realm!token-id` |
| `proxmox.api_token` | Token secret from the Proxmox UI |
| `proxmox.root_ssh_key_location` | Private key path for host access |
| `proxmox.insecure` | Skip TLS verification (default: true) |
| `proxmox.ssh_username` / `proxmox.node_name` | SSH user and Proxmox node |
| `vm_ssh_pub_key` | Public key deployed to created VMs/LXC |
| `admin_username` | Admin user for services (must match the vault) |

See `terraform/variables.tf` for types and defaults. The state file is gitignored.

> **The API user needs the `Administrator` role on `/`.** Narrower scopes break Terraform:
> per-VMID paths cannot cover VMIDs that do not exist yet, so creating a new host 403s; and image
> downloads need node-level privileges (`query-url-metadata`, `download-url`) that `PVEVMAdmin`
> does not grant.
>
> ```bash
> pveum user add tf-infra@pve --enable 1
> pveum aclmod / -user tf-infra@pve -role Administrator
> pveum user token add tf-infra@pve tf --privsep 0
> ```
>
> Bind mounts and device passthrough on LXC can only be applied by `root@pam` itself, so those are
> handled out-of-band by the `ansible-pve-host` playbook over SSH.

### 3. Configure the vault

Edit `ansible/group_vars/all/vault.yml` (gitignored). `admin_username` must match
`terraform.tfvars`.

```bash
# Generate the AdGuard bcrypt hash ($2a$)
sudo apt install apache2-utils
htpasswd -bnBC 10 "" 'yourpassword' | tr -d ':\n' | sed 's/$2y/$2a/'
```

### 4. Configure external USB disks

Point `external_disks[].by_id` in `ansible/group_vars/pve.yml` at the drives to mount. Find the
stable by-id name on the Proxmox host:

```bash
ssh root@192.168.1.100 "ls -l /dev/disk/by-id/ | grep -i usb"
```

`make all` detects the filesystem and mounts it persistently by UUID at `/mnt/pve/<name>` before
Terraform creates the containers. `assert_dirs` must already exist on the drive; `create_dirs` is
created if missing.

## First Deployment

```bash
make tf-plan     # preview
make all         # ansible-pve → tf-init → tf-apply → ansible-pve-host → ansible-all
```

`make all` runs `ssh-accept-keys` first, so stale host keys after a VM rebuild are handled
automatically. Run the steps individually with `make tf-init`, `make tf-apply`,
`make ansible-all`, or a single role via `make ansible-adguard` / `ansible-docker` /
`ansible-plex` / `ansible-k3s`.

On a **fresh** deployment, shift the shared template resource address first (the module gained a
`count`), or Terraform will try to destroy and recreate it:

```bash
terraform state mv 'module.adguard_home.module.adguard_lxc.proxmox_virtual_environment_file.debian_template' 'module.adguard_home.module.adguard_lxc.proxmox_virtual_environment_file.debian_template[0]'
```

Then wire the local tools (each prompts for sudo):

```bash
make kubectl-setup    # kubectl + ~/.kube/config
make helmfile-setup   # helmfile + helm-diff, verified against the cluster
make apps             # deploy everything in apps/k3s/helmfile.yaml
```

Claim Plex once from a browser at `http://192.168.1.103:32400/web` and point a library at
`/PlexMedia`.

## Verification

```bash
docker info                              # Docker VM is up
nslookup google.com 192.168.1.101        # AdGuard resolving
ssh root@192.168.1.103 "findmnt /PlexMedia && ls /dev/dri"   # Plex mounts
kubectl get nodes                        # K3s Ready
helmfile --file apps/k3s/helmfile.yaml diff   # empty == cluster matches the state file
```

The empty helmfile diff is the useful health check: it means the running releases are exactly what
the state file declares, so `make apps` will be a no-op. Anything else means either the state file
drifted or something changed the cluster outside Helm — read the diff before applying.

`make kubectl-setup` handles the kubeconfig properly: the playbook fetches it to
`ansible/playbooks/files/k3s.yaml` (gitignored) with `server: https://127.0.0.1:6443`, and the
target patches that to the LAN IP before copying it to `~/.kube/config` with mode 600. Prefer it
over editing the file by hand.

## Next Steps

1. **Client DNS** — see [Local Network Setup](network-setup.md).
2. **Deploy apps** — see [Apps](../apps/README.md). Docker apps on `.102` use the
   `*.docker.internal` wildcard; K3s apps use the `*.k3s.internal` wildcard, so neither needs a
   per-app DNS rewrite.
3. **Retire the old Plex container (`.150`)** once `.103` is verified: `pct destroy 100` and reclaim
   the orphaned volume. It is not managed by Terraform.

## Troubleshooting

### SSH host key changed

Terraform recreated a VM, so its host key changed.

```bash
make ssh-cleanup     # clear stale keys for .100, .102, .104
```

`make all` does this automatically; it only bites on manual `make ansible-*` runs.

### Terraform cannot reach Proxmox

- Check `terraform.tfvars` credentials and that `curl -k https://192.168.1.100:8006` responds
- `proxmox.node_name` must match the real Proxmox node name

### Docker VM not accessible

- Verify the VM is running and the SSH key matches: `ssh -i ~/.ssh/id_ed25519 <user>@192.168.1.102`
- Check the data disk is mounted (`lsblk` / `mount | grep docker-data`)

### AdGuard dashboard unreachable

- Check the LXC is running and port 80 is not blocked: `curl http://192.168.1.101`
- TLS certs live in `/opt/AdGuardHome/certs/`

### K3s / kubectl

- **`dial tcp 127.0.0.1:6443`** — the kubeconfig still points at loopback. Run `make kubectl-config`
  rather than editing by hand.
- **`Missing ansible/playbooks/files/k3s.yaml`** — the file is fetched by `make ansible-k3s`; it is
  gitignored and is not fetched until that playbook runs.
- **`certificate signed by unknown authority`** — a stale or hand-edited `~/.kube/config`. Re-fetch
  with `make ansible-k3s && make kubectl-config`.
- **Node `NotReady`** — on `.104`, check `systemctl status k3s` and the firewall ports
  (6443/10250/8472).
- **SSH timeout** — `make ssh-cleanup` then `make ssh-accept-keys`.

### Helm / helmfile

- **`sudo: a terminal is required to read the password`** — the install targets shell out to `sudo`
  for the move into `/usr/local/bin`. Run from a terminal, or install the binary yourself into
  `~/.local/bin` and put it on `PATH`. Not usable from CI as written.
- **`Kubernetes cluster unreachable` / `x509: certificate signed by unknown authority`** — Helm and
  helmfile read the same `~/.kube/config` as kubectl. Fix the kubeconfig first.
- **`diff: command not found`** — helm-diff is missing; `make apps` needs it too, since helmfile
  implements `apply` through it. Run `make helmfile-setup`.
- **`plugin verification failed: open .../pubring.gpg`** — Helm 4 found no key to verify the plugin
  against. `make helmfile-setup` passes `keys/helm-diff.gpg` via `--keyring`; if you install by
  hand, pass it too.
- **Chart `kubeVersion` rejected** — a hard failure, not a warning. Pin a chart version compatible
  with `v1.36.4+k3s1`.
- **`cannot be imported into the current release`** — Helm will not adopt resources that were
  created outside Helm. Delete them before the first chart install.
- **A release shows as `DELETED` in the diff** — expected if its `installed:` flag is `false`;
  `make apps` will uninstall it. See [Apps](../apps/README.md#retiring-a-release).
- **Pods stay Pending with no diff** — Helm 4's default wait is watcher-based and fails fast on
  charts with a `livenessProbe` but no `startupProbe`. Add `trackMode: helm-legacy` to the release
  or to `helmDefaults`. Harmless warning on Helm 3.
