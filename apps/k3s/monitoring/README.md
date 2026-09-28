# Prometheus + Grafana

Deployed with [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts),
pinned to chart **91.8.1** in the `monitoring-install` Makefile target. Overrides live in
[values.yaml](values.yaml).

```bash
make monitoring-install     # helm upgrade --install (idempotent)
make monitoring-password    # print the generated Grafana admin password
```

| URL | What |
| --- | --- |
| `https://grafana.k3s.internal` | Grafana — user `admin` |
| `https://grafana-prometheus.k3s.internal` | Prometheus UI |

Both hostnames resolve through the existing `*.k3s.internal` AdGuard wildcard, so no DNS
rewrite was needed. Note the cluster serves the Traefik default self-signed certificate on
443 — expect a browser warning, same as the Headlamp ingress.

`monitoring-delete` uninstalls the release, but the PVCs are StatefulSet
`volumeClaimTemplate`s and survive it. Reclaim them with
`kubectl delete pvc -n monitoring --all` (that is what drops metrics history).

## Storage

The PVCs use k3s's `local-path` class and are sized against this node's 8.2 GiB of
allocatable storage: 4Gi Prometheus, 1Gi Grafana, 500Mi Alertmanager. `local-path` has
`reclaimPolicy=Delete` and `allowVolumeExpansion=false`, so a PVC cannot be grown in place
— resizing means deleting it and losing the data.

## The kubelet override (do not remove)

k3s disables anonymous authentication on the kubelet, so the chart's stock kubelet
ServiceMonitor gets `HTTP 401` and the target never comes up. Every container and cAdvisor
panel on the bundled dashboards is then empty. The kubelet's serving certificate is also
signed by the k3s serving CA rather than the cluster CA, so TLS verification would fail
too.

`values.yaml` therefore sets `kubelet.serviceMonitor.enabled: false` and supplies three
`additionalScrapeConfigs` jobs that authenticate with the Prometheus pod's own projected
service-account token. No extra RBAC is needed: the operator's default ClusterRole already
grants that ServiceAccount `nodes/metrics`.

Check it took effect:

```bash
curl -sk 'https://grafana-prometheus.k3s.internal/api/v1/targets?state=active' \
  | grep -o '"health":"[a-z]*"' | sort | uniq -c
```

All 13 targets should be `up`.

## Verifying

```bash
helm list -n monitoring
kubectl get pods,pvc -n monitoring
curl -sk --get 'https://grafana-prometheus.k3s.internal/api/v1/query' \
  --data-urlencode 'query=sum(container_memory_working_set_bytes{container!=""})'
```

The last command proves the cAdvisor path end to end — it only returns data because of the
kubelet override above.
