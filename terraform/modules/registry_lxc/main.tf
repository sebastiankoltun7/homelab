module "registry_lxc" {
  source   = "../proxmox_lxc"
  id       = var.id
  lxc_name = var.name
  tags     = concat(["management-plane"], var.tags)

  # Network
  ip_address      = var.ip
  ip_gateway      = "192.168.1.1"
  enable_firewall = true

  # Resources (Allocated extra disk space for image blob caching)
  disk_datastore_id = "local-lvm"
  cores             = 2
  memory            = 2048
  disk_size         = 30

  # Template
  template_datastore_id = "local"
  os_template_source    = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
  os_template_type      = "debian"

  # Admin Access
  user_account_ssh_public_keys = [var.ssh_pub_key]
}

module "registry_firewall" {
  source       = "../proxmox_firewall"
  container_id = var.id
  node_name    = "pve"

  # Inbound traffic entering the Registry
  inbound_rules = [
    {
      port    = "5000"
      proto   = "tcp"
      source  = "192.168.1.0/24"
      comment = "Allow K3s nodes to pull from registry mirror (TCP 5000)"
    },
    {
      port    = "22"
      source  = "192.168.1.0/24"
      comment = "Allow SSH management from local network"
    }
  ]

  # Outbound traffic leaving the Registry (Needs internet access to proxy/pull missing layers)
  outbound_rules = [
    {
      port    = "53"
      proto   = "udp"
      comment = "Allow outbound DNS resolution (UDP)"
    },
    {
      port    = "53"
      proto   = "tcp"
      comment = "Allow outbound DNS resolution (TCP)"
    },
    {
      port    = "80"
      proto   = "tcp"
      comment = "Allow outbound HTTP for upstream registries"
    },
    {
      port    = "443"
      proto   = "tcp"
      comment = "Allow outbound HTTPS for upstream registries (Docker Hub, Quay, GHCR)"
    }
  ]
}

// Overrides / Variables
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
  value = module.registry_lxc.template_file_id
}