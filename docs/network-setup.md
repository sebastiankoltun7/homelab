# Local Network Setup

## Network Overview

| Host | IP | Purpose |
|------|-----|---------|
| Gateway | 192.168.1.1 | Router |
| Proxmox | 192.168.1.100 | Hypervisor host |
| AdGuard | 192.168.1.101 | DNS ad blocking + admin UI |
| Docker | 192.168.1.102 | Container runtime |
| Plex | 192.168.1.103 | Plex Media Server |
| K3s | 192.168.1.104 | K3s single-node (Traefik, Flannel) |

Subnet: `192.168.1.0/24` · The K3s kubeconfig is wired locally with `mise run kubectl-config`.

## IP Assignment

Terraform assigns static IPs to the lab hosts (`.101`-`.104`). Reserve `.100`-`.110` in your
router's DHCP pool and give the Proxmox host a static DHCP reservation — otherwise a power cycle or
lease renewal can hand a lab IP to a different device and break the network.

## DNS

AdGuard Home at `192.168.1.101` is the lab's resolver, and it answers the lab's hostnames itself:

- `*.k3s.skoltun.dev` → K3s VM, `*.docker.skoltun.dev` → Docker VM
- `adguard.homelab` → AdGuard, `plex.homelab` → Plex

Point clients at it — best by handing out `192.168.1.101` as DNS from your router's DHCP (or by
running DHCP in AdGuard). A client that uses AdGuard needs no manual entries; the public DNS for
the domain knows nothing about the LAN. Clients that bypass AdGuard need the hostnames mapped by
hand.

Verify:

```bash
nslookup google.com 192.168.1.101
```

## HTTPS

Every HTTPS endpoint is served with a Let's Encrypt certificate issued inside the K3s cluster — see
[Apps](../apps/README.md#tls-for-the-ingresses). AdGuard's dashboard is plain HTTP
(`http://192.168.1.101`).
