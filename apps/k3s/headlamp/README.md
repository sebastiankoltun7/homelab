# Headlamp setup

Deployed with the official [Headlamp chart](https://kubernetes-sigs.github.io/headlamp/)
(`headlamp/headlamp`), pinned to chart/app version **0.45.0** in the `headlamp-install`
Makefile target. Overrides live in [values.yaml](values.yaml).

```bash
make headlamp-install   # add repo + helm upgrade --install (idempotent)
make headlamp-token     # print a login token
```

Visit https://dashboard.k3s.internal and paste the token when prompted.

The chart creates the `headlamp` namespace, a `headlamp-admin` ServiceAccount bound to
`cluster-admin`, and the Traefik ingress. `values.yaml` keeps the
`headlamp-admin` name so the token command above stays stable.

Verify or inspect:

```bash
helm list -n headlamp
helm get values headlamp -n headlamp
kubectl get all,ingress -n headlamp
```

Tear down with `make headlamp-delete` (leaves the namespace in place).

## Migrating from the raw manifest

The chart is the source of truth now; the old `headlamp.yaml` is gone. It was applied
with `kubectl`, so its resources carried no Helm ownership metadata and `helm install`
refuses to adopt them:

```
Error: unable to continue with install: ServiceAccount "headlamp-admin" in namespace
"headlamp" exists and cannot be imported into the current release
```

So a first-time migration must remove the old objects before installing:

```bash
git rm apps/k3s/headlamp/headlamp.yaml
kubectl delete -f apps/k3s/headlamp/headlamp.yaml --ignore-not-found
make headlamp-install
```

Expect a short gap in availability while the pod is replaced.
