terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}

locals {
  template_file_id = coalesce(
    var.template_file_id,
    try(proxmox_virtual_environment_file.debian_template[0].id, "")
  )
}

# Download debian OS template unless an existing template file is shared
resource "proxmox_virtual_environment_file" "debian_template" {
  count        = var.template_file_id == null ? 1 : 0
  content_type = "vztmpl"
  datastore_id = var.template_datastore_id
  node_name    = "pve"

  source_file {
    path = var.os_template_source
  }
}

# Provision the LXC Container
resource "proxmox_virtual_environment_container" "lxc_container" {
  node_name     = "pve"
  vm_id         = var.id
  tags          = var.tags
  start_on_boot = true

  unprivileged = true
  features {
    nesting = true
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }
  cpu {
    cores = var.cores
  }

  operating_system {
    template_file_id = local.template_file_id
    type             = var.os_template_type
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
    name     = "eth0"
    bridge   = "vmbr0"
    firewall = var.network_firewall
  }

  dynamic "startup" {
    for_each = var.startup_order != null ? [var.startup_order] : []
    content {
      order = startup.value
    }
  }

  disk {
    datastore_id = var.disk_datastore_id
    size         = var.disk_size
  }

  dynamic "mount_point" {
    for_each = var.apply_mount_points ? var.mount_points : []
    content {
      volume = mount_point.value.volume
      path   = mount_point.value.path
    }
  }

  # Bind mounts and device passthrough can only be applied by user root@pam
  # (not by an API token), so they are configured out-of-band by the Ansible
  # "setup_pve_host" playbook via `pct`. Keep Terraform declarative in code but
  # ignore the runtime drift it can never manage itself.
  lifecycle {
    ignore_changes = [mount_point]
  }

  dynamic "device_passthrough" {
    for_each = var.device_passthrough
    content {
      path = device_passthrough.value.path
    }
  }

  depends_on = [proxmox_virtual_environment_file.debian_template]
}