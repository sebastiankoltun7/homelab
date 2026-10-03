# Apps

Two mechanisms, and only two:

| Where | How | State lives in |
| --- | --- | --- |
| Docker VM (`.102`) | `docker compose` | `apps/docker/<name>/` |
| K3s cluster (`.104`) | `helmfile` | `apps/k3s/helmfile.yaml` |

Anything that does not fit one of these two does not belong in this repo. Individual apps are not
documented here — they are described by their compose file, their `values.yaml`, and the state
file entry.

## Docker Compose apps

`apps/docker/<name>/docker-compose.yml`. Every app must attach to the external `proxy-net`
bridge, which is created by Ansible:

```yaml
networks:
  proxy-net:
    external: true
services:
  myapp:
    networks: [proxy-net]
    environment:
      VIRTUAL_HOST: myapp.docker.skoltun.dev
```

Deploy and check:

```bash
mise run docker-context                                # once per machine
docker --context homelab compose -f apps/docker/<name>/docker-compose.yml up -d
docker --context homelab compose -f apps/docker/<name>/docker-compose.yml logs -f
```

`nginx-proxy` auto-discovers anything on `proxy-net` and routes by `VIRTUAL_HOST`. Hostnames under
`*.docker.skoltun.dev` already resolve to the Docker VM via an AdGuard wildcard, so new apps usually
need no DNS change.

Secrets go in `.env`, which is gitignored. Commit `.env.template` with placeholder values only.

## K3s apps (helmfile)

All releases are declared in one state file, [`k3s/helmfile.yaml`](k3s/helmfile.yaml), with
per-app overrides in `apps/k3s/<name>/values.yaml`. Values paths resolve relative to the state
file, so the commands below work from anywhere.

```bash
mise install          # once: helmfile + kubectl + helm, pinned in .mise.toml
mise run helm-diff     # once: the helm-diff plugin helmfile needs
mise run kubectl-config # once: ~/.kube/config from the fetched k3s.yaml
mise run apps-diff     # preview what would change
mise run apps          # install/upgrade everything (idempotent)
mise run apps-list     # list declared releases
mise run apps-destroy  # uninstall everything
```

`mise run all` runs `apps` for you after the cluster exists, after `helm-diff` and `kubectl-config`.

`helm`, `helmfile` and `kubectl` come from [`.mise.toml`](../.mise.toml), and mise tasks run with
those versions in `PATH`, so they do not depend on your shell having run `mise activate`. When
calling helmfile directly, use `mise exec --` (or run it in an activated shell):

```bash
mise exec -- helmfile --file apps/k3s/helmfile.yaml diff   -l name=<release>
mise exec -- helmfile --file apps/k3s/helmfile.yaml apply  -l name=<release>
mise exec -- helmfile --file apps/k3s/helmfile.yaml destroy -l name=<release>
```

`mise run apps` prints the app URLs and how to fetch their credentials when it finishes.

## TLS for the ingresses

`*.k3s.skoltun.dev` resolves through the AdGuard wildcard, and every ingress that declares a `tls`
block gets a **Let's Encrypt** certificate from cert-manager — no self-signed certificates and
nothing to trust on client machines. Three pieces make that work:

1. **cert-manager** is the first release in `k3s/helmfile.yaml` (chart `jetstack/cert-manager`), so it
   is installed before anything that references a `ClusterIssuer`.
2. **The Cloudflare API token** is read from Bitwarden (item `Cloudflare token (HomeLab)`) by
   `mise run apps` and stored as the `cloudflare-api-token-secret` secret in the `cert-manager`
   namespace. That step lives in the task, not in the state file, so the token never lands in git.
3. **The ClusterIssuer** in [`k3s/cluster-issuer.yaml`](k3s/cluster-issuer.yaml) (`letsencrypt-prod`,
   DNS-01 + Cloudflare) is applied by `mise run apps` *after* the helmfile sync, because it needs the
   CRDs cert-manager installs.

To give a release a certificate, add to its `values.yaml`:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  tls:
    - secretName: myapp-tls
      hosts: [myapp.k3s.skoltun.dev]
```

DNS-01 needs no inbound port 80 and works from a private LAN, but it does require the Cloudflare
token to be allowed to edit DNS for the zone. An ingress without a `tls` block keeps Traefik's
self-signed default — that is why `grafana-prometheus.k3s.skoltun.dev` still shows a browser warning.

```bash
kubectl get certificate          # headlamp-tls and grafana-tls should be Ready True
kubectl describe clusterissuer letsencrypt-prod
```

## Logging in

Nothing here is stored in the repo. Read the credentials out of the cluster:

```bash
mise run headlamp-token       # Headlamp login token, valid 24h
mise run monitoring-password  # generated Grafana admin password
```

| Service | URL | Login |
|---------|-----|-------|
| Headlamp | `https://dashboard.k3s.skoltun.dev` | paste the `headlamp-token` output into the token login box |
| Grafana | `https://grafana.k3s.skoltun.dev` | user `admin`, password from `monitoring-password` |
| Prometheus | `https://grafana-prometheus.k3s.skoltun.dev` | none |

Headlamp's token comes from the `headlamp-admin` service account bound to `cluster-admin` in
`k3s/headlamp/values.yaml`, so re-run `mise run headlamp-token` whenever the 24h one expires.
Grafana's password is generated by the chart and stored in the `monitoring-grafana` secret; it only
changes if the Grafana PVC is deleted.

Headlamp and Grafana get Let's Encrypt certificates (see [TLS for the ingresses](#tls-for-the-ingresses)).
Prometheus has no `tls` block, so it keeps Traefik's self-signed default and the browser warns once
per host until you accept it.

## Managing releases

### Adding a release

Add a repository (once) and a release entry, then `mise run apps-diff` to review:

```yaml
repositories:
  - name: <repo>
    url: https://<repo-url>

releases:
  - name: <release>
    installed: true
    namespace: <namespace>
    createNamespace: true
    chart: <repo>/<chart>
    version: '{{ env "<RELEASE>_CHART_VERSION" | default "<pinned>" }}'
    values:
      - <release>/values.yaml
```

Pin the chart version in the state file. The env-var indirection is optional but lets you try a
version without editing the file:

```bash
<RELEASE>_CHART_VERSION=1.2.3 mise run apps-diff
```

### Retiring a release

Set `installed: false` and run `mise run apps`. The diff reports the release as `DELETED` and the
apply uninstalls it; the entry stays in the file so flipping it back redeploys.

Use `condition:` instead if you only want helmfile to ignore an entry without uninstalling it.

## Gotchas

These are properties of k3s and Helm, not of any particular app:

- **Helm will not adopt existing objects.** Migrating a raw `kubectl apply` manifest to a chart
  fails with `cannot be imported into the current release`; delete the old objects first.
- **Chart `kubeVersion` is a hard check.** A chart requiring a newer Kubernetes than the server
  fails outright rather than warning. Pin a compatible chart version.
- **k3s disables anonymous kubelet auth**, so a chart's stock kubelet ServiceMonitor gets `401`
  and any dashboard fed by it stays empty. Override it with `additionalScrapeConfigs` that
  authenticate with the Prometheus pod's own token.
- **k3s `local-path` PVCs cannot be expanded in place** (`allowVolumeExpansion=false`,
  `reclaimPolicy=Delete`), and they are not removed when a release is uninstalled. Reclaim them
  with `kubectl delete pvc -n <namespace> --all`, which discards the data.
- **An ingress without a `tls` block gets Traefik's self-signed certificate**, so browsers warn on
  that hostname. Add the `tls` block and the `cert-manager.io/cluster-issuer` annotation to get a
  trusted certificate instead.
- **`apps-destroy` does not remove the `ClusterIssuer` or the Cloudflare secret** — both live outside
  the helmfile state. `kubectl delete clusterissuer letsencrypt-prod` and
  `kubectl -n cert-manager delete secret cloudflare-api-token-secret` if you want a clean slate.

## Which mechanism?

- Needs its own kernel-level isolation, local files, or a specific runtime → Docker.
- Anything stateful that benefits from backups, scheduling, or ingress → K3s.
- Not sure → Docker; it is cheaper to undo.
