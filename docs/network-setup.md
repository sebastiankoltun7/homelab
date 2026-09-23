# Local Network Setup

## Network Overview

| Host | IP | Purpose |
|------|-----|---------|
| Gateway | 192.168.1.1 | Router |
| AdGuard | 192.168.1.101 | DNS ad blocking + admin UI |
| Docker | 192.168.1.102 | Container runtime |

Subnet: `192.168.1.0/24`

## DHCP and IP Assignment

This setup assumes your router uses default DHCP (automatically assigns IPs from a pool).

**Important:** Terraform assigns static IPs to the homelab hosts (`.101`, `.102`). To prevent your router from assigning these IPs to other devices:

1. **Set static DHCP reservation for Proxmox host** (`.100`) in your router
2. **Reserve the homelab IP range** (`.100-.110`) in your router's DHCP pool to avoid collisions

Without this, a power cycle or DHCP lease renewal could assign `192.168.1.101` to a different device, breaking your network.

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

## Trusting the AdGuard TLS certificate

AdGuard Home serves its admin dashboard over `https://adguard.internal`. Because the certificate is self-signed (no public CA), browsers will warn "Your connection is not private" until you install it as a trusted certificate.

The Ansible playbook generates the certificate and fetches a copy to `ansible/playbooks/files/cert.crt`. Install/trust that file on any machine that should open the dashboard over HTTPS without warnings:

```bash
# Verify the cert and its name
openssl x509 -in ansible/playbooks/files/cert.crt -noout -subject -ext subjectAltName
```

Then import it per your OS:

### Windows

Via PowerShell (admin):

```powershell
Import-Certificate -FilePath "cert.crt" -CertStoreLocation Cert:\LocalMachine\Root
```

Or via `certutil` (admin):

```powershell
certutil -addstore -f Root cert.crt
```

Or GUI: double-click `cert.crt` → **Install Certificate** → **Local Machine** → **Trusted Root Certification Authorities**. Reopen the browser afterwards (Chrome/Edge read the Windows cert store at startup).

To uninstall later: `certutil -delstore Root <thumbprint>` or get the thumbprint with `Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like "*adguard*"`.

### Linux

Debian/Ubuntu (system-wide):

```bash
sudo cp cert.crt /usr/local/share/ca-certificates/adguard.crt
sudo update-ca-certificates
```

Then add the hostname to `/etc/hosts` if you don't use AdGuard as your DNS server:

```
192.168.1.101 adguard.internal
```

Fedora/RHEL:

```bash
sudo cp cert.crt /etc/pki/ca-trust/source/anchors/adguard.crt
sudo update-ca-trust
```

**Chrome/Edge** on Linux uses the NSS store; import there too:

```bash
certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n "AdGuard" -i cert.crt
```

Or use the GUI: `chrome://settings/certificates` → Authorities → Import.

**Firefox** uses its own store:
1. Settings → Privacy & Security → Certificates → **View Certificates** → Authorities → **Import**.
2. Select `cert.crt` and tick "Trust this CA to identify websites".

### macOS

1. Double-click `cert.crt` → Keychain Access opens.
2. Drag/copy the certificate into the **System** keychain (or click the lock, choose "Add to Keychain").
3. Double-click the certificate → expand **Trust** → set **When using this certificate** → **Always Trust**.
4. Close the window, enter your password to confirm. Restart the browser.

Or via CLI:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain cert.crt
```

### Verifying

```bash
curl --cacert ansible/playbooks/files/cert.crt https://adguard.internal
curl --cacert ansible/playbooks/files/cert.crt https://192.168.1.101
```

If either returns the AdGuard dashboard HTML (not a TLS error), the certificate is trusted.

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
open https://adguard.internal   # after trusting the cert
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
- HTTPS address in config: `https://adguard.internal` (needs the cert trusted, see above)
- LXC container is running in Proxmox
- No firewall blocking ports 80/443

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
