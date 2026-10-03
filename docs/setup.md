# Initial Setup Guide

Step-by-step setup for the homelab from scratch. For deploying apps, see [Apps](../apps/README.md).

## Prerequisites

[mise](https://mise.jdx.dev/getting-started.html) is the only tool installed by hand. Everything
else the CLI needs is pinned in [`.mise.toml`](../.mise.toml) and installed by `mise install` — no
`brew`, no `apt`, no `sudo mv` into `/usr/local/bin`.

| Tool | Version | Installed by |
| --- | --- | --- |
| mise | any recent | manual, once |
| Python | 3.12 | `mise install` |
| Terraform | 1.16 | `mise install` |
| kubectl | 1.37.1 | `mise install` |
| Helm | 4.3.0 | `mise install` |
| helmfile | 1.8.0 | `mise install` |
| Bitwarden CLI | latest | `mise install` |
| Ansible | 2.14+ | `mise run setup-venv` (creates `ansible/.venv`) |

`mise run tools` prints the resolved version of each tool, so it doubles as a verification step.
Mise tasks run with the pinned versions in `PATH`, so the versions in `.mise.toml` are used even in
a shell where `mise activate` never ran.

Also needed, and not managed by mise:

- **Bitwarden CLI** authenticated against a vault holding three items (see
  [Credentials](#credentials-from-bitwarden)).
- **A domain you control** (`skoltun.dev` throughout this repo), delegated to Cloudflare, plus a
  Cloudflare API token with **Zone: DNS / Edit** rights for that zone. It is used for Let's Encrypt
  DNS-01 challenges, so every HTTPS endpoint gets a publicly trusted certificate — see
  [Domain and certificates](#5-domain-and-certificates).
- **`jq`** and **OpenSSH** — used by the `ssh-key` and `terraform-auth` tasks.
- **Docker** — `mise run install-docker-local` installs the client on Linux/WSL2 (and adds your user
  to the `docker` group). It is the client only; the Docker VM at `.102` is the runtime.
- **sudo and `losetup`** — only for `mise run bake-image`, which loop-mounts a Raspberry Pi image.

Tested versions: Terraform 1.16.x, kubectl `v1.37.1` against server `v1.36.4+k3s1`, Helm `v4.3.0`,
helmfile `1.8.0`, helm-diff `3.15.15`.

> **Helm 4 vs 3:** Helm 4 defaults to server-side apply for *new* releases and renames
> `--atomic` → `--rollback-on-failure` and `--force` → `--force-replace`. Releases created by
> Helm 3 keep client-side apply after an upgrade. If a chart misbehaves, pin Helm 3 in
> `.mise.toml` (`mise use helm@3.22.0`) and re-run `mise install`.

## Proxmox Setup

### 1. Enable API Token Authentication

1. Log in to the Proxmox web UI
2. **Datacenter** > **Permissions** > **API Tokens** > **Add**
3. Select (or create) a user — never `root@pam`
4. Check **Privilege Separation: No**, so the token inherits the user's ACLs
5. Note the **Token ID** and **Token Secret**

### 2. Add your SSH key to the Proxmox host

Terraform and Ansible both reach the host over SSH. `mise run ssh-key` imports your key from
Bitwarden to `~/.ssh/id_ed25519` and loads it into `ssh-agent`, so all that is left is registering
it with Proxmox:

```bash
mise run ssh-key        # fetches the key from Bitwarden (no-op if ~/.ssh/id_ed25519 exists)
ssh-copy-id root@192.168.1.100
ssh root@192.168.1.100  # should not prompt
```

## Configuration

### 1. Run setup

```bash
mise run setup
```

One bootstrap task, in dependency order:

| Task | What it does |
| --- | --- |
| `tools` | `mise install`, then prints each tool's version |
| `install-docker-local` | installs Docker and adds your user to the `docker` group |
| `ssh-key` | imports `homelab-ssh-key` from Bitwarden into `~/.ssh`, loads ssh-agent |
| `terraform-auth` | writes `~/.terraform.d/credentials.tfrc.json` from the `hcp-terraform-token` Bitwarden item (interactive) |
| `ansible-install` | `setup-venv` (creates `ansible/.venv` with `ansible-core`, `paramiko`, `proxmoxer`, `requests`) then installs the pinned collections |
| `vault-create` | copies `vault.yml` from the template if missing |
| `terraform-tfvars` | copies `terraform.tfvars` from the template if missing |

Activate the venv to run `ansible-playbook` directly:

```bash
source ansible/.venv/bin/activate
```

Individual pieces are available if you need only one: `mise run vault-create`, `mise run
terraform-tfvars`, `mise run ansible-install`, `mise run clean` (removes the venv).

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
> handled over SSH instead of through the Proxmox API — the first play of `install_plex.yml` runs
> against the `pve` group (`192.168.1.100`) and does the bind mounts, GPU entries and disk mounts
> itself.

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

`ansible/tasks/configure_external_disk.yml` (run by the first play of `install_plex.yml`) detects the
filesystem and mounts it persistently by UUID at `/mnt/pve/<name>`, then binds `/PlexMedia` and
`/plex-config` into the Plex container. Because it runs from `mise run ansible-plex` — which
`ansible-all` and `mise run all` call after `tf-apply` — the Plex container must already exist, and
the task fails fast if the drive is not attached. `assert_dirs` must already exist on the drive;
`create_dirs` is created if missing.

### 5. Domain and certificates

All hostnames live under `skoltun.dev`, delegated to Cloudflare, and every HTTPS endpoint uses a real
Let's Encrypt certificate obtained through the DNS-01 challenge — no self-signed certificates and
nothing to trust on client machines. Two places consume the same Cloudflare API token:

- `mise run ansible-adguard` (and `ansible-all`) requests a `skoltun.dev` + `*.skoltun.dev`
  wildcard certificate for AdGuard Home with certbot.
- `mise run apps` stores the token in the `cert-manager` namespace and applies
  `apps/k3s/cluster-issuer.yaml`, so cert-manager issues certificates for the K3s ingresses.

Keep the token in Bitwarden (item `Cloudflare token (HomeLab)`) with **Zone: DNS / Edit** rights for
`skoltun.dev`. See [HTTPS certificates](network-setup.md#https-certificates) and
[Apps](../apps/README.md#tls-for-the-ingresses).

### Credentials from Bitwarden

Several tasks read from Bitwarden, all expecting the CLI to be installed (`mise install`) and the
vault unlocked. Export `BW_SESSION=$(bw unlock --raw)` once to skip the interactive prompt;
`terraform-auth` is flagged interactive and always prompts when the session is missing.

| Task | Bitwarden item | Field | Used for |
| --- | --- | --- | --- |
| `mise run ssh-key`, `mise run bake-image` | `homelab-ssh-key` | `sshKey.privateKey` / `.sshKey.publicKey` | SSH key written to `~/.ssh/id_ed25519[.pub]` and loaded into ssh-agent; the public key baked into the Pi image |
| `mise run terraform-auth` | `hcp-terraform-token` | `notes` | written to `~/.terraform.d/credentials.tfrc.json` for `app.terraform.io` |
| `mise run ansible-adguard`, `ansible-all`, `ansible-dry-run`, `apps` | `Cloudflare token (HomeLab)` | `login.password` | Let's Encrypt DNS-01 challenges for AdGuard and for cert-manager |

`ansible-dry-run` falls back to a placeholder token when the vault is locked, since certbot is not
reached in check mode.

`ssh-key` is a no-op when `~/.ssh/id_ed25519` already exists, so it never overwrites a key you
generated yourself.

## First Deployment

```bash
mise run tf-plan    # preview
mise run all        # ansible-install → ssh-cleanup → ssh-accept-keys → terraform-auth →
                    # tf-init → tf-apply → wait-for-vms → ansible-all → docker-context →
                    # kubectl-config → helm-diff → apps
```

`mise run all` accepts SSH host keys first, so stale host keys after a VM rebuild are handled
automatically. Run the steps individually with `mise run tf-init`, `mise run tf-apply`,
`mise run ansible-all`, or a single role via `mise run ansible-adguard` / `ansible-docker` /
`ansible-plex` / `ansible-k3s`. The manual `ansible-*` tasks accept host keys too, but only `all`
clears stale ones first.

On a **fresh** deployment, shift the shared template resource address first (the module gained a
`count`), or Terraform will try to destroy and recreate it:

```bash
terraform state mv 'module.adguard_home.module.adguard_lxc.proxmox_virtual_environment_file.debian_template' 'module.adguard_home.module.adguard_lxc.proxmox_virtual_environment_file.debian_template[0]'
```

`all` ends by wiring the local tools and deploying the cluster apps, so these are already done
afterwards — run them individually only when re-doing that part:

```bash
mise run kubectl-config    # ~/.kube/config from the fetched k3s.yaml
mise run helm-diff         # helm-diff plugin, verified against the cluster
mise run docker-context    # remote Docker context "homelab"
mise run apps              # deploy everything in apps/k3s/helmfile.yaml
```

Claim Plex once from a browser at `http://192.168.1.103:32400/web` and point a library at
`/PlexMedia`.

## Logging in

`mise run apps` prints the URLs below when it finishes. Credentials are read out of the cluster
rather than stored in the repo:

```bash
mise run headlamp-token        # Headlamp login token, valid 24h
mise run monitoring-password   # generated Grafana admin password
```

| Service | URL | Login |
|---------|-----|-------|
| Headlamp | `https://dashboard.k3s.skoltun.dev` | paste the `headlamp-token` output into the token login box |
| Grafana | `https://grafana.k3s.skoltun.dev` | user `admin`, password from `monitoring-password` |
| Prometheus | `https://grafana-prometheus.k3s.skoltun.dev` | none |
| AdGuard Home | `https://adguard.skoltun.dev` | `admin_username` + the AdGuard password from `vault.yml` |
| Plex | `http://192.168.1.103:32400/web` | claim once, then your Plex account |

The Headlamp token is minted from the `headlamp-admin` service account (`cluster-admin`), so it is
as powerful as root in the cluster and expires after 24h — re-run the task for a new one. The
Grafana password is generated by the chart on first install and lives in the
`monitoring-grafana` secret; it survives `mise run apps-destroy` only as long as the PVC does.

The Headlamp and Grafana ingresses get Let's Encrypt certificates from cert-manager, so those two
URLs are warning-free. Prometheus has no `tls` block in
`apps/k3s/monitoring/values.yaml`, so `grafana-prometheus.k3s.skoltun.dev` still falls back to
Traefik's self-signed default and the browser asks you to accept it once.

## Verification

```bash
docker info                              # Docker VM is up (remote context "homelab")
nslookup google.com 192.168.1.101        # AdGuard resolving
curl https://adguard.skoltun.dev         # AdGuard dashboard over a trusted certificate
ssh root@192.168.1.103 "findmnt /PlexMedia && ls /dev/dri"   # Plex mounts
kubectl get nodes                        # K3s Ready
kubectl get pods -n cert-manager          # cert-manager running
kubectl get certificate                   # headlamp-tls / grafana-tls issued and Ready
helmfile diff -f apps/k3s/helmfile.yaml  # empty == cluster matches the state file
```

`kubectl get certificate` needs a few seconds after the first `mise run apps`: cert-manager solves
the DNS-01 challenge first. If a certificate stays `Pending`, check the ClusterIssuer and the
`cloudflare-api-token-secret`:

```bash
kubectl describe clusterissuer letsencrypt-prod
kubectl get events -n cert-manager --sort-by=.lastTimestamp | tail
```

Run the `kubectl` and `helmfile` commands through mise (`mise exec -- ...`) if your shell has not
activated it, or use the mise tasks, which always run with the pinned tools.

The empty helmfile diff is the useful health check: it means the running releases are exactly what
the state file declares, so `mise run apps` will be a no-op. Anything else means either the state
file drifted or something changed the cluster outside Helm — read the diff before applying.

`mise run kubectl-config` handles the kubeconfig properly: the playbook fetches it to
`ansible/playbooks/files/k3s.yaml` (gitignored) with `server: https://127.0.0.1:6443`, and the
task patches that to the LAN IP before copying it to `~/.kube/config` with mode 600. Prefer it
over editing the file by hand.

## Next Steps

1. **Client DNS** — see [Local Network Setup](network-setup.md).
2. **Deploy apps** — see [Apps](../apps/README.md). Docker apps on `.102` use the
   `*.docker.skoltun.dev` wildcard; K3s apps use the `*.k3s.skoltun.dev` wildcard, so neither needs a
   per-app DNS rewrite.
3. **Retire the old Plex container (`.150`)** once `.103` is verified: `pct destroy 100` and reclaim
   the orphaned volume. It is not managed by Terraform.

## Troubleshooting

### SSH host key changed

Terraform recreated a VM, so its host key changed.

```bash
mise run ssh-cleanup     # clear stale keys for .100, .102, .104
```

`mise run all` does this automatically; it only bites on manual `mise run ansible-*` runs.

### Terraform cannot reach Proxmox

- Check `terraform.tfvars` credentials and that `curl -k https://192.168.1.100:8006` responds
- `proxmox.node_name` must match the real Proxmox node name
- Remote state needs the HCP token: re-run `mise run terraform-auth`

### Docker VM not accessible

- Verify the VM is running and the SSH key matches: `ssh -i ~/.ssh/id_ed25519 <user>@192.168.1.102`
- Check the data disk is mounted (`lsblk` / `mount | grep docker-data`)
- `permission denied` on the Docker socket locally: the `install-docker-local` task adds you to the
  `docker` group, but a new group needs a fresh login (or `wsl --shutdown` on WSL)

### Bitwarden tasks fail

- **`bw: command not found`** — `mise install` did not finish, or the shell has not picked up
  mise's shims.
- **`You are not logged in`** — unlock the vault, or export `BW_SESSION=$(bw unlock --raw)`.
- **Missing item** — `homelab-ssh-key`, `hcp-terraform-token` and `Cloudflare token (HomeLab)` must
  exist in the vault the CLI is pointed at. `terraform-auth` reads the token from the item's notes
  field, the Cloudflare token from `login.password`; both fail if the secret was stored elsewhere.

### AdGuard dashboard unreachable

- Check the LXC is running and port 80 is not blocked: `curl http://192.168.1.101`
- TLS certs live in `/opt/AdGuardHome/certs/`, copied from `/etc/letsencrypt/live/skoltun.dev/`
- **certbot fails** — usually the Cloudflare token lacks DNS edit rights for the zone, or the domain
  is not on the Cloudflare account the token belongs to. The vault must be unlocked for
  `mise run ansible-adguard` to get the token at all.

### Certificates do not get issued

- **`no such host` / Cloudflare API errors in `certbot` or `cert-manager` logs** — the token in
  Bitwarden is wrong or lacks Zone: DNS / Edit for `skoltun.dev`.
- **`unauthorized` from the ACME server** — the account email in
  `apps/k3s/cluster-issuer.yaml` / the certbot command is not reachable, or you hit the
  duplicate-certificate rate limit.
- **Certificate `Pending` forever** — the ClusterIssuer was never applied. `mise run apps` applies
  `apps/k3s/cluster-issuer.yaml` after the helmfile sync; re-run it, or check
  `kubectl get clusterissuer`.
- **Rate limits** — Let's Encrypt allows 5 duplicate certificates per week; prefer waiting for the
  existing one over forcing a re-issue.

### K3s / kubectl

- **`dial tcp 127.0.0.1:6443`** — the kubeconfig still points at loopback. Run `mise run
  kubectl-config` rather than editing by hand.
- **`Missing ansible/playbooks/files/k3s.yaml`** — the file is fetched by `mise run ansible-k3s`; it
  is gitignored and is not fetched until that playbook runs.
- **`certificate signed by unknown authority`** — a stale or hand-edited `~/.kube/config`. Re-fetch
  with `mise run ansible-k3s && mise run kubectl-config`.
- **Node `NotReady`** — on `.104`, check `systemctl status k3s` and the firewall ports
  (6443/10250/8472).
- **SSH timeout** — `mise run ssh-cleanup` then `mise run ssh-accept-keys`.

### Helm / helmfile

- **`mise: not found`** — only mise itself is installed by hand. See
  [mise.jdx.dev/getting-started](https://mise.jdx.dev/getting-started.html).
- **`unknown command "diff" for "helm"`** — the helm-diff plugin is missing. It is not optional:
  helmfile implements `apply` as diff-then-sync, so `mise run apps` needs it too. Run `mise run
  helm-diff`.
- **`Kubernetes cluster unreachable` / `x509: certificate signed by unknown authority`** — Helm and
  helmfile read the same `~/.kube/config` as kubectl. Fix the kubeconfig first.
- **`no such file or directory` on the plugin tarball** — `mise run helm-diff` fetches the official
  linux-amd64 release asset; on arm64 install the plugin with your platform's asset from
  <https://github.com/databus23/helm-diff/releases>.
- **A different tool version than `.mise.toml` says** — something earlier on `PATH` is shadowing it.
  Mise tasks are immune because they run inside mise's environment; a bare `terraform` or `helm` in
  your shell is not, if that shell never ran `mise activate`. Use `mise exec -- <tool>`.
- **Chart `kubeVersion` rejected** — a hard failure, not a warning. Pin a chart version compatible
  with `v1.36.4+k3s1`.
- **`cannot be imported into the current release`** — Helm will not adopt resources that were
  created outside Helm. Delete them before the first chart install.
- **A release shows as `DELETED` in the diff** — expected if its `installed:` flag is `false`;
  `mise run apps` will uninstall it. See [Apps](../apps/README.md#retiring-a-release).
- **Pods stay Pending with no diff** — Helm 4's default wait is watcher-based and fails fast on
  charts with a `livenessProbe` but no `startupProbe`. Add `trackMode: helm-legacy` to the release
  or to `helmDefaults`. Harmless warning on Helm 3.
