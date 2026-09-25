terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}

module "plex_lxc" {
  source   = "../proxmox_lxc"
  id       = var.id
  lxc_name = var.name
  tags     = concat(["media-plane"], var.tags)

  # Network
  ip_address = var.ip
  ip_gateway = "192.168.1.1"
  enable_firewall = true

  # Resources
  cores             = 3
  memory            = 1024
  swap              = 512
  disk_datastore_id = "local-lvm"
  disk_size         = 8
  template_file_id = var.template_file_id

  # Template
  os_template_type   = "debian"

  # Admin Access
  user_account_ssh_public_keys = [var.ssh_pub_key]
}

module "plex_firewall" {
  source       = "../proxmox_firewall"
  container_id = var.id
  node_name    = "pve"

  # Inbound traffic entering Plex
  inbound_rules = [
    {
      port    = "32400"
      comment = "Allow Plex Media Server traffic"
    },
    {
      port    = "22"
      source  = "192.168.1.0/24"
      comment = "Allow SSH from local network only"
    }
  ]

  # Outbound traffic leaving Plex
  outbound_rules = [
    # Allow outbound DNS lookups
    {
      port    = "53"
      proto   = "udp"
      comment = "Allow outbound DNS lookups"
    },
    {
      port    = "53"
      proto   = "tcp"
      comment = "Allow outbound DNS lookups (TCP)"
    },

    # Allow outbound HTTPS for metadata, trailers, and core updates
    {
      port    = "443"
      proto   = "tcp"
      comment = "Allow outbound HTTPS (metadata, updates)"
    },

    # 3. Block scanning/access to private IP ranges
    {
      dest    = "192.168.0.0/16"
      action  = "DROP"
      comment = "Block local subnet scanning"
      log = "info"
    },
    {
      dest    = "10.0.0.0/8"
      action  = "DROP"
      comment = "Block private Class A networks"
      log = "info"
    },
    {
      dest    = "172.16.0.0/12"
      action  = "DROP"
      comment = "Block private Class B networks"
      log = "info"
    }
  ]
}