module "adguard_lxc" {
  source   = "../proxmox_lxc"
  id       = var.id
  lxc_name = var.name
  tags     = concat(["management-plane"], var.tags)

  # Network
  ip_address = var.ip
  ip_gateway = "192.168.1.1"
  enable_firewall = true

  # Resources
  disk_datastore_id = "local-lvm"
  cores             = 1
  memory            = 512
  disk_size         = 8

  # Template
  template_datastore_id = "local"
  os_template_source    = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
  os_template_type      = "debian"

  # Admin Access
  user_account_ssh_public_keys = [var.ssh_pub_key]
}

module "adguard_firewall" {
  source       = "../proxmox_firewall"
  container_id = var.id
  node_name    = "pve"

  # Inbound traffic entering AdGuard
  inbound_rules = [
    {
      port    = "53"
      proto   = "udp"
      comment = "Allow DNS queries from network clients (UDP)"
    },
    {
      port    = "53"
      proto   = "tcp"
      comment = "Allow DNS queries from network clients (TCP)"
    },
    {
      port    = "3000"
      source  = "192.168.1.0/24"
      comment = "Allow AdGuard Web UI (Default port)"
    },
    {
      port    = "80"
      proto   = "tcp"
      source  = "192.168.1.0/24"
      comment = "Allow AdGuard HTTP web UI / rewrites from local network"
    },
    {
      port    = "443"
      proto   = "tcp"
      source  = "192.168.1.0/24"
      comment = "Allow AdGuard HTTPS web UI / TLS from local network"
    },
    {
      port    = "22"
      source  = "192.168.1.0/24"
      comment = "Allow SSH from local network only"
    }
  ]

  # Outbound traffic leaving AdGuard (Isolated from LAN scanning)
  outbound_rules = [
    {
      port    = "53"
      proto   = "udp"
      comment = "Allow outbound upstream DNS (UDP)"
    },
    {
      port    = "53"
      proto   = "tcp"
      comment = "Allow outbound upstream DNS (TCP)"
    },
    {
      port    = "853"
      proto   = "tcp"
      comment = "Allow DNS-over-TLS (DoT) to upstream resolvers"
    },
    {
      port    = "443"
      proto   = "tcp"
      comment = "Allow outbound HTTPS for blocklists and updates"
    },

    # Block scanning/access to private IP ranges (LAN isolation)
    {
      dest    = "192.168.0.0/16"
      action  = "DROP"
      comment = "Block local subnet scanning"
      log     = "info"
    },
    {
      dest    = "10.0.0.0/8"
      action  = "DROP"
      comment = "Block private Class A networks"
      log     = "info"
    },
    {
      dest    = "172.16.0.0/12"
      action  = "DROP"
      comment = "Block private Class B networks"
      log     = "info"
    }
  ]
}

//Overrides
variable "id" {
  type = number
}
variable "name" {
  type = string
}
variable "tags" {
  type = list(string)
}
variable "ip" {
  type = string
}
variable "ssh_pub_key" {
  type = string
}

output "lxc_template_file_id" {
  value = module.adguard_lxc.template_file_id
}
