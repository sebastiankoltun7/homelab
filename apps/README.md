# Apps

Docker Compose apps deployed to the Docker VM (`192.168.1.102`). All apps share the external `proxy-net` bridge created by `ansible/playbooks/install_docker.yml:58` — required for `nginx-proxy` auto-discovery.

## Prerequisites

- Homelab provisioned: `make all` (creates `proxy-net`)
- Docker context (optional): `make docker-context` (`DOCKER_USER ?= skoltun`)
- For remote deploy: `docker context use homelab`

Verify network:

```bash
docker network ls | grep proxy-net
```

## Apps

### nginx-proxy (`docker/nginx`)

`nginxproxy/nginx-proxy:latest` with auto-discovery. Routes by `VIRTUAL_HOST` env. Shares ports `80`/`443` on the Docker VM.

```bash
# Deploy with homelab context
docker --context homelab compose -f apps/docker/nginx/docker-compose.yml up -d

# Or SSH
ssh skoltun@192.168.1.102 "docker compose -f /path/to/nginx/docker-compose.yml up -d"
```

Volumes: `nginx_certs`, `nginx_vhost`, `nginx_html`, `nginx_conf`. Mounts `docker.sock` read-only.

### MinIO (`docker/mini_io`)

S3-compatible storage. Uses `quay.io/minio/minio:latest` with console `:9001` and S3 `:9000`.

```bash
cp apps/docker/mini_io/.env.template apps/docker/mini_io/.env
$EDITOR apps/docker/mini_io/.env  # set strong MINIO_PASS
docker --context homelab compose -f apps/docker/mini_io/docker-compose.yml up -d
```

Env (`apps/docker/mini_io/.env.template:1`):

```
DOMAIN=docker.internal
MINIO_USER=admin
MINIO_PASS=changeme
```

Routing via `VIRTUAL_HOST_MULTIPORTS` (requires `nginx-proxy` + DNS rewrites, templated with `${DOMAIN}` in `apps/docker/mini_io/docker-compose.yml:14`):

- `minio.docker.internal` → `:9001` (console)
- `s3.minio.docker.internal` → `:9000` (S3 API)

DNS wildcard `*.docker.internal → 192.168.1.102` is already configured in `ansible/group_vars/role_adguard.yml:20`, so `minio.docker.internal` resolves without extra rewrites.

## Kubernetes apps (`k3s/`)

Apps deployed to the K3s cluster (`192.168.1.104`). These do **not** use `proxy-net` — ingress is Traefik, and names are resolved by the `*.k3s.internal → 192.168.1.104` wildcard in `ansible/group_vars/role_adguard.yml:30`.

Prerequisites:

```bash
make kubectl-setup  # wire ~/.kube/config (server https://192.168.1.104:6443)
make helm-setup     # optional: install Helm for chart-based apps
```

### Headlamp (`k3s/headlamp`)

Kubernetes dashboard, deployed with the pinned official chart (0.45.0) and
[values.yaml](k3s/headlamp/values.yaml).

```bash
make headlamp-install   # helm upgrade --install (idempotent)
```

Get a token and open `https://dashboard.k3s.internal` — see [k3s/headlamp/README.md](k3s/headlamp/README.md).

### Prometheus + Grafana (`k3s/monitoring`)

Metrics, dashboards and alerting, deployed with the pinned kube-prometheus-stack chart
(91.8.1) and [values.yaml](k3s/monitoring/values.yaml).

```bash
make monitoring-install     # helm upgrade --install (idempotent)
make monitoring-password    # generated Grafana admin password
```

Grafana at `https://grafana.k3s.internal` (user `admin`), Prometheus UI at
`https://grafana-prometheus.k3s.internal` — see
[k3s/monitoring/README.md](k3s/monitoring/README.md).

The values file carries a k3s-specific kubelet scrape override; the bundled dashboards are
empty without it, so don't strip it.

### Installing a chart

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm search repo cert-manager
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace
helm list -A
```

Charts must declare a `kubeVersion` compatible with the server (`v1.36.4+k3s1`); a newer constraint is a hard error, not a warning. Prefer OCI or digest-pinned installs for anything that pulls from a third-party registry.

## Adding a New App

1. Create `apps/docker/<name>/docker-compose.yml` (and `.env.template` if needed — never commit `.env`).
2. Attach to external network:

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

3. Add DNS rewrite for `myapp.docker.internal` in `ansible/group_vars/role_adguard.yml:20` if outside the `*.docker.internal` wildcard (the wildcard already covers any `*.docker.internal → 192.168.1.102`), then re-run `make ansible-adguard`.
4. Deploy via `docker --context homelab compose up -d`.

For a Kubernetes app, put it under `apps/k3s/<name>/` instead: raw manifests are applied with `kubectl apply -f`, charts with `helm install` (`--version` pinned). No `proxy-net` and no AdGuard rewrite is needed — the `*.k3s.internal` wildcard already covers every hostname.

## Secrets

`.env` files are gitignored (`/.gitignore:25`). Commit only `.env.template` with placeholder values (e.g., `changeme`). Example: `apps/docker/mini_io/.env` (ignored) vs `apps/docker/mini_io/.env.template` (tracked).

## Notes

- `apps/k3s/headlamp/` is chart-based: the pinned chart version lives in the `headlamp-install` Makefile target and overrides in `values.yaml`, not a `Chart.lock` committed from a local run. Prefer the same layout for new chart-based apps.
- Resource limits: MinIO capped at `512M` / `2 cpus` (`apps/docker/mini_io/docker-compose.yml:28`).
- All Docker apps expect `proxy-net` — `docker compose` will fail if Ansible hasn't created it. Kubernetes apps do not.
