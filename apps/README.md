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
      VIRTUAL_HOST: myapp.docker.internal
```

Deploy and check:

```bash
make docker-context                                # once per machine
docker --context homelab compose -f apps/docker/<name>/docker-compose.yml up -d
docker --context homelab compose -f apps/docker/<name>/docker-compose.yml logs -f
```

`nginx-proxy` auto-discovers anything on `proxy-net` and routes by `VIRTUAL_HOST`. Hostnames under
`*.docker.internal` already resolve to the Docker VM via an AdGuard wildcard, so new apps usually
need no DNS change.

Secrets go in `.env`, which is gitignored. Commit `.env.template` with placeholder values only.

## K3s apps (helmfile)

All releases are declared in one state file, [`k3s/helmfile.yaml`](k3s/helmfile.yaml), with
per-app overrides in `apps/k3s/<name>/values.yaml`. Values paths resolve relative to the state
file, so the commands below work from anywhere.

```bash
make tools           # once: helmfile + kubectl + helm, pinned in .mise.toml
make helm-diff       # once: the helm-diff plugin helmfile needs
make kubectl-config  # once: ~/.kube/config from the fetched k3s.yaml
make apps-diff       # preview what would change
make apps            # install/upgrade everything (idempotent)
make apps-list       # list declared releases
make apps-destroy    # uninstall everything
```

`helm`, `helmfile` and `kubectl` come from [`.mise.toml`](../../.mise.toml) and are invoked through
`mise exec`, so the `make` targets do not depend on your shell having run `mise activate`. When
calling helmfile directly, use `mise exec --` (or run it in an activated shell):

```bash
mise exec -- helmfile --file apps/k3s/helmfile.yaml diff   -l name=<release>
mise exec -- helmfile --file apps/k3s/helmfile.yaml apply  -l name=<release>
mise exec -- helmfile --file apps/k3s/helmfile.yaml destroy -l name=<release>
```

`make apps` prints the app URLs and how to fetch their credentials when it finishes.

### Adding a release

Add a repository (once) and a release entry, then `make apps-diff` to review:

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
<RELEASE>_CHART_VERSION=1.2.3 make apps-diff
```

### Retiring a release

Set `installed: false` and run `make apps`. The diff reports the release as `DELETED` and the
apply uninstalls it; the entry stays in the file so flipping it back redeploys.

Use `condition:` instead if you only want helmfile to ignore an entry without uninstalling it.

### Gotchas

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
- **The cluster serves Traefik's self-signed certificate** on 443, so browsers warn on ingress
  hostnames. That is expected.

## Which mechanism?

- Needs its own kernel-level isolation, local files, or a specific runtime → Docker.
- Anything stateful that benefits from backups, scheduling, or ingress → K3s.
- Not sure → Docker; it is cheaper to undo.
