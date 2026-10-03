# Local Network Setup

## Network Overview

| Host | IP | Purpose |
|------|-----|---------|
| Gateway | 192.168.1.1 | Router |
| AdGuard | 192.168.1.101 | DNS ad blocking + admin UI |
| Docker | 192.168.1.102 | Container runtime |
| Plex | 192.168.1.103 | Plex Media Server |
| K3s | 192.168.1.104 | K3s single-node (Traefik, Flannel) |

Subnet: `192.168.1.0/24` · K3s kubeconfig wired via `mise run kubectl-config` (`ansible/playbooks/files/k3s.yaml` -> `~/.kube/config`)

## DHCP and IP Assignment

This setup assumes your router uses default DHCP (automatically assigns IPs from a pool).

**Important:** Terraform assigns static IPs to the homelab hosts (`.101`-`.104`). To prevent your router from assigning these IPs to other devices:

1. **Set static DHCP reservation for Proxmox host** (`.100`) in your router
2. **Reserve the homelab IP range** (`.100-.110`) in your router's DHCP pool to avoid collisions

Without this, a power cycle or DHCP lease renewal could assign `192.168.1.101` to a different device, breaking your network.

## DNS Setup Options

### Option 1: Router DNS (Simplest)

Set your router's DNS server to `192.168.1.101`. The router distributes this DNS via DHCP to all clients.

**Pros:** Zero client config, all devices covered automatically.

**Cons:** Some routers don't support custom DNS; some IoT devices use hardcoded DNS and bypass router settings.

### Option 2: DHCP via AdGuard (Recommended)

1. Disable DHCP on your router
2. Enable DHCP in AdGuard Home (Settings > DHCP settings) on `192.168.1.101` — configure gateway `192.168.1.1`, subnet `192.168.1.0/24`, range outside static IPs (e.g., `.110-.250`), and DNS `192.168.1.101` (DHCP option 6)
3. AdGuard advertises itself as DNS via DHCP; clients get AdGuard as their DNS automatically

Alternatively, keep DHCP on the router but set its DNS/DHCP option 6 to `192.168.1.101` if your router supports it (functionally Option 1).

**Pros:** Full control over DNS, all devices covered, no per-client config.

**Cons:** Requires router admin access; if AdGuard/LXC is down, DHCP/DNS are down — keep Option 1 or 3 as fallback.

### Option 3: Manual Client Configuration

Set DNS manually on each device to `192.168.1.101`.

**Pros:** No router changes needed.

**Cons:** Doesn't scale; must configure each device individually.

## Client Configuration

If you do not point a client at AdGuard as its DNS server, map the hostnames you use by hand — the
public DNS for `skoltun.dev` knows nothing about your LAN:

```
192.168.1.101 adguard.skoltun.dev
192.168.1.104 dashboard.k3s.skoltun.dev grafana.k3s.skoltun.dev grafana-prometheus.k3s.skoltun.dev
192.168.1.102 <app>.docker.skoltun.dev
```

### Windows

Set DNS via PowerShell:

```powershell
# Set DNS for current adapter
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "192.168.1.101"

# Disable auto-configured DNS
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses
```

Disable IPv6 (required if DNS fails with NXDOMAIN):

```powershell
Set-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6 -Enabled $false
```

### Linux (NetworkManager)

```bash
# Set DNS server
nmcli con mod "Connection Name" ipv4.dns "192.168.1.101"

# Ignore DHCP-provided DNS
nmcli con mod "Connection Name" ipv4.ignore-auto-dns yes

# Restart connection
nmcli con down "Connection Name" && nmcli con up "Connection Name"
```

Disable IPv6:

```bash
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
```

### macOS

1. System Preferences > Network > Select connection > Advanced
2. DNS tab > Click `+` > Add `192.168.1.101`
3. TCP/IP tab > Configure IPv6: Link-local only

## HTTPS certificates

AdGuard Home serves its admin dashboard over `https://adguard.skoltun.dev` with a **Let's Encrypt
wildcard certificate** for `skoltun.dev` + `*.skoltun.dev`, issued by the Ansible playbook with
certbot's DNS-01 challenge against Cloudflare. Since it is a publicly trusted certificate, browsers
and `curl` accept it out of the box — there is nothing to install and no warning to click through.

Requirements and consequences:

- `skoltun.dev` must be delegated to Cloudflare, and the Cloudflare API token in Bitwarden (item
  `Cloudflare token (HomeLab)`) must be allowed to edit DNS records for that zone. DNS-01 needs no
  inbound port 80 and no public DNS record for the container, so it works from a private LAN.
- The certificate covers hostnames only. `https://192.168.1.101` is **not** covered — use the
  hostname, or plain `http://192.168.1.101`, which AdGuard still serves.
- The K3s ingresses get their own certificates from cert-manager through the same DNS-01 solver; see
  [Apps](../apps/README.md#tls-for-the-ingresses).

Verify:

```bash
curl https://adguard.skoltun.dev          # dashboard HTML, no --cacert needed
```

If you hit a certificate error, the usual causes are a stale browser cache, a client that still has
the old self-signed certificate pinned as a trusted root (remove it), or a DNS response from a
different resolver than AdGuard.

## Verifying DNS is Working

```bash
# Test resolution against AdGuard
nslookup google.com 192.168.1.101
nslookup adguard.skoltun.dev 192.168.1.101
nslookup app.docker.skoltun.dev 192.168.1.101  # docker apps: *.docker.skoltun.dev → 192.168.1.102 (ansible/group_vars/role_adguard.yml:21)

# Test from Linux/Mac
dig @192.168.1.101 google.com
dig @192.168.1.101 adguard.skoltun.dev
dig @192.168.1.101 app.docker.skoltun.dev

# Check AdGuard dashboard
open http://192.168.1.101
open https://adguard.skoltun.dev
```

Verify queries appear in AdGuard's query log after visiting an ad-heavy site.

## Upstream DNS

Configure in AdGuard dashboard (Settings > DNS settings):

| Provider | Servers | Notes |
|----------|---------|-------|
| Google | 8.8.8.8, 8.8.4.4 | Default, fast |
| Cloudflare | 1.1.1.1, 1.0.0.1 | Privacy-focused |
| Quad9 | 9.9.9.9, 149.112.112.112 | Security-focused |
| Custom | Your choice | Add your own |

## Common Issues

### DNS_PROBE_FINISHED_NXDOMAIN

**Cause:** Windows forces IPv6 DNS when IPv6 is unavailable.

**Fix:** Disable IPv6 on your network adapter (see Windows section above).

### DNS not resolving

**Check:**
- AdGuard is running: `systemctl status AdGuardHome` on the LXC container
- Port 53 is accessible: `telnet 192.168.1.101 53`
- Firewall rules not blocking DNS traffic

### IoT devices not using AdGuard

**Cause:** Devices use hardcoded DNS (e.g., `8.8.8.8`).

**Fix:** Block outbound port 53 to anything except `192.168.1.101` in your router's firewall.

### Dashboard unreachable

**Check:**
- HTTP address in config: `192.168.1.101:80`
- HTTPS address in config: `https://adguard.skoltun.dev` (publicly trusted certificate, see
  [HTTPS certificates](#https-certificates))
- LXC container is running in Proxmox
- No firewall blocking ports 80/443
- Certificate issued? `certbot certificates` on `192.168.1.101` — if the request failed, AdGuard is
  serving with a stale or missing chain

### High latency

**Cause:** Upstream DNS server slow.

**Fix:** Change upstream DNS in AdGuard settings to a closer/faster provider.

## Troubleshooting Commands

```bash
# Linux/Mac - test DNS resolution
dig @192.168.1.101 google.com
dig @192.168.1.101 adguard.skoltun.dev
dig @192.168.1.101 app.docker.skoltun.dev  # docker wildcard

# Windows - test DNS resolution
nslookup google.com 192.168.1.101
nslookup adguard.skoltun.dev 192.168.1.101
nslookup app.docker.skoltun.dev 192.168.1.101

# Check if port 53 is open
telnet 192.168.1.101 53

# Check AdGuard service status (on LXC)
systemctl status AdGuardHome
```
