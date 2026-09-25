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

## Secrets

`.env` files are gitignored (`/.gitignore:25`). Commit only `.env.template` with placeholder values (e.g., `changeme`). Example: `apps/docker/mini_io/.env` (ignored) vs `apps/docker/mini_io/.env.template` (tracked).

## Notes

- `apps/k3s/` was removed (empty placeholder). File an issue if you want k3s support re-added.
- Resource limits: MinIO capped at `512M` / `2 cpus` (`apps/docker/mini_io/docker-compose.yml:28`).
- All apps expect `proxy-net` — `docker compose` will fail if Ansible hasn't created it.
