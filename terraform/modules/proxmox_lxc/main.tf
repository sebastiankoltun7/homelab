terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}

# Download debian OS template 
resource "proxmox_virtual_environment_file" "debian_template" {
  content_type = "vztmpl"
  datastore_id = var.template_datastore_id
  node_name    = "pve"

  source_file {
    path = var.os_template_source
  }
}

# Provision the LXC Container
resource "proxmox_virtual_environment_container" "lxc_container" {
  node_name = "pve"
  vm_id     = var.id
  tags      = var.tags

  unprivileged = true
  features {
    nesting = true
  }

  memory {
    dedicated = var.memory
  }
  cpu {
    cores = var.cores
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_file.debian_template.id
    type = var.os_template_type
  }

  initialization {
    hostname = var.lxc_name
    user_account {
      keys = var.user_account_ssh_public_keys
    }
    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.ip_gateway
      }
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  disk {
    datastore_id = var.disk_datastore_id
    size         = var.disk_size
  }

  depends_on = [proxmox_virtual_environment_file.debian_template]
}
