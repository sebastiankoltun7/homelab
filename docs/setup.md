# Initial Setup Guide

Step-by-step guide to set up the homelab from scratch.

## Prerequisites

### Install Tools

#### Terraform

```bash
# macOS
brew install terraform

# Linux (Debian/Ubuntu)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Windows
choco install terraform
```

#### Ansible

```bash
# macOS / Linux
pip install ansible

# Ubuntu
sudo apt install ansible
```

#### Docker

```bash
# macOS
brew install --cask docker

# Linux (Debian/Ubuntu)
sudo apt install docker.io

# Windows
choco install docker-desktop
```

#### Python 3.12+

```bash
# macOS
brew install python@3.12

# Linux (Debian/Ubuntu)
sudo apt install python3.12 python3.12-venv

# Windows
choco install python
```

#### Make

```bash
# macOS
xcode-select --install

# Linux (Debian/Ubuntu)
sudo apt install make

# Windows (Git Bash includes make, or)
choco install make
```

#### OpenSSH

Usually pre-installed on all platforms. Verify with:

```bash
ssh -V
ssh-keygen -V
```

### Proxmox Setup

#### 1. Enable API Token Authentication

1. Log in to Proxmox web UI (https://PROXMOX_IP:8006)
2. Go to **Datacenter** > **Permissions** > **API Tokens**
3. Click **Add**
4. Select a user (or create one, e.g., `terraform@pam`)
5. Check **Privilege Separation: No** (allows full API access)
6. Note the **Token ID** and **Token Secret**

#### 2. Generate SSH Key Pair

Generate an SSH key pair for Proxmox and VM access:

```bash
# Generate key (if you don't have one)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Copy public key to Proxmox host
ssh-copy-id root@192.168.1.100
```

#### 3. Add SSH Key to Proxmox Host

The public key needs to be on the Proxmox host for Terraform to connect:

```bash
# Copy to Proxmox root
ssh-copy-id root@192.168.1.100

# Or manually
cat ~/.ssh/id_ed25519.pub | ssh root@192.168.1.100 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

## Configuration

### 1. Run Setup

```bash
make setup
```

This creates:
- Python virtual environment
- Config files from templates (skips if they exist)

### 2. Configure Terraform

Edit `terraform/terraform.tfvars`:

```hcl
proxmox = {
  ip                    = "192.168.1.100"    # Proxmox host IP
  port                  = "8006"             # Proxmox API port
  username              = "terraform@pve!terraform-token"  # API token format
  api_token             = "terraform@pam!token_id=xxxxxxxx" # Token value
  root_ssh_key_location = "~/.ssh/id_ed25519" # SSH private key path
}
vm_ssh_pub_key    = "ssh-ed25519 AAAA..."     # Public key for VMs
admin_username    = "your-username"            # Admin user for all services
```

**Fields explained:**

| Field | Description |
|-------|-------------|
| `proxmox.ip` | Proxmox host IP address |
| `proxmox.port` | Proxmox web UI port (default: 8006) |
| `proxmox.username` | API token in format `user@realm!token-id` |
| `proxmox.api_token` | Token secret from Proxmox UI |
| `proxmox.root_ssh_key_location` | Path to SSH private key for Proxmox/VM access |
| `vm_ssh_pub_key` | Public key deployed to created VMs |
| `admin_username` | Username created on VMs and used for services |

### 3. Configure Ansible Vault

Edit `ansible/group_vars/all/vault.yml`:

```yaml
admin_username: "your-username"
adguard_admin_password_hash: "$2a$10$..."  # bcrypt hash
```

**Generate bcrypt hash:**

```bash
# Install htpasswd (usually pre-installed on macOS/Linux)
# macOS
brew install httpd

# Linux
sudo apt install apache2-utils

# Generate hash
htpasswd -bnBC 10 "" 'yourpassword' | tr -d ':\n' | sed 's/$2y/$2a/'
```

**Note:** `admin_username` must match the value in `terraform.tfvars`.

## First Deployment

### 1. Preview Changes

```bash
make tf-plan        # Preview infrastructure changes
```

### 2. Deploy Infrastructure

```bash
make all            # Full deployment (Terraform + Ansible)
```

Or step by step:

```bash
make tf-init        # Initialize Terraform
make tf-apply       # Create LXC and VM
make ansible-install # Install Ansible collections
make ansible-all    # Configure services
```

### 3. What Happens

1. **Terraform** creates:
   - AdGuard LXC container (Debian 13) at `192.168.1.101`
   - Docker VM (Ubuntu 24.04) at `192.168.1.102`

2. **Ansible** configures:
   - AdGuard Home DNS server with ad blocking
   - Docker engine with `proxy-net` bridge network

## Verification

### Check Infrastructure

```bash
# Proxmox - verify VMs are running
# Web UI: https://192.168.1.100:8006

# SSH into Docker VM
ssh your-username@192.168.1.102

# Check Docker is running
docker info
```

### Check AdGuard

```bash
# Open dashboard
open http://192.168.1.101

# Test DNS resolution
nslookup google.com 192.168.1.101

# Test internal DNS
nslookup adguard.internal 192.168.1.101
```

### Check Docker Context

```bash
# Setup remote Docker context
make docker-context

# Test
docker ps
```

## Next Steps

1. **Configure client DNS** — See [Local Network Setup](network-setup.md)
2. **Deploy apps** — Add docker-compose files to `apps/docker/`
3. **Add DNS rewrites** — Edit `ansible/group_vars/role_adguard.yml`

## Troubleshooting

### Terraform fails to connect to Proxmox

- Verify API token credentials in `terraform.tfvars`
- Check Proxmox IP and port are reachable: `curl -k https://192.168.1.100:8006`

### Ansible SSH timeout

- Run `make ssh-cleanup` to remove stale host keys
- Verify SSH key is on Proxmox host: `ssh root@192.168.1.100`

### AdGuard dashboard unreachable

- Check LXC is running in Proxmox UI
- Verify port 80 is not blocked: `curl http://192.168.1.101`

### Docker VM not accessible

- Check VM is running in Proxmox UI
- Verify SSH key matches: `ssh -i ~/.ssh/id_ed25519 your-username@192.168.1.102`
