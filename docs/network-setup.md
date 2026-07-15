# Local Network Setup

## Network Overview

| Host | IP | Purpose |
|------|-----|---------|
| Gateway | 192.168.1.1 | Router |
| AdGuard | 192.168.1.101 | DNS ad blocking + admin UI |
| Docker | 192.168.1.102 | Container runtime |

Subnet: `192.168.1.0/24`

## DNS Setup Options

### Option 1: Router DNS (Simplest)

Set your router's DNS server to `192.168.1.101`. The router distributes this DNS via DHCP to all clients.

**Pros:** Zero client config, all devices covered automatically.

**Cons:** Some routers don't support custom DNS; some IoT devices use hardcoded DNS and bypass router settings.

### Option 2: DHCP with AdGuard (Recommended)

1. Disable DHCP on your router
2. Set router's DHCP to point to AdGuard (`192.168.1.101`)
3. AdGuard advertises itself as DNS via DHCP option 6

**Pros:** Full control over DNS, all devices covered.

**Cons:** Requires router admin access; if homelab goes down, you don't have web access.

### Option 3: Manual Client Configuration

Set DNS manually on each device to `192.168.1.101`.

**Pros:** No router changes needed.

**Cons:** Doesn't scale; must configure each device individually.

## Client Configuration

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

## Verifying DNS is Working

```bash
# Test resolution against AdGuard
nslookup google.com 192.168.1.101
nslookup adguard.internal 192.168.1.101

# Test from Linux/Mac
dig @192.168.1.101 google.com
dig @192.168.1.101 adguard.internal

# Check AdGuard dashboard
open http://192.168.1.101
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

**Fix:** Block external DNS at router/firewall (see Firewall Rules section).

### Dashboard unreachable

**Check:**
- HTTP address in config: `192.168.1.101:80`
- LXC container is running in Proxmox
- No firewall blocking port 80

### High latency

**Cause:** Upstream DNS server slow.

**Fix:** Change upstream DNS in AdGuard settings to a closer/faster provider.

## Troubleshooting Commands

```bash
# Linux/Mac - test DNS resolution
dig @192.168.1.101 google.com
dig @192.168.1.101 adguard.internal

# Windows - test DNS resolution
nslookup google.com 192.168.1.101
nslookup adguard.internal 192.168.1.101

# Check if port 53 is open
telnet 192.168.1.101 53

# Check AdGuard service status (on LXC)
systemctl status AdGuardHome
```
