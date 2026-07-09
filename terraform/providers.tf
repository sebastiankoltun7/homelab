terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
  cloud {
    organization = "Koltuns-HomeLab"
    workspaces {
      name = "homelab-infra"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://${var.proxmox.ip}:${var.proxmox.port}/"
  username  = var.proxmox.username
  api_token = var.proxmox.api_token
  insecure  = true

  ssh {
    agent       = true
    username    = "root"
    node {
      name    = "pve"
      address = var.proxmox.ip
    }
  }
  
}
