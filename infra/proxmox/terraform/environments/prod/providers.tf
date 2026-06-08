terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://${var.proxmox.ip}:${var.proxmox.port}/"
  username  = var.proxmox.username
  api_token = var.proxmox.api_token
  insecure  = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file(var.proxmox.root_ssh_key_location)
    node {
      name    = "pve"
      address = var.proxmox.ip
    }
  }
}
