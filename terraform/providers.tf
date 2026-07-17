terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
  // Delete this block to use local tf state
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
  insecure  = var.proxmox.insecure

  ssh {
    agent    = true
    username = var.proxmox.ssh_username
    node {
      name    = var.proxmox.node_name
      address = var.proxmox.ip
    }
  }
}
