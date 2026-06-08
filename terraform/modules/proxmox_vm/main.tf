
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}

locals {
  boot_interfaces = [for d in var.vm_disks : d.interface if d.is_boot_disk]
}

# Fetch & unpack distro image
resource "proxmox_download_file" "distro_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = "pve"
  file_name    = endswith(basename(var.distro_image_url), ".img") ? replace(basename(var.distro_image_url), ".img", ".qcow2") : basename(var.distro_image_url)
  url          = var.distro_image_url
  # After creating vm do not change it
  overwrite           = false
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "vm_node" {
  name      = "${var.vm_name}-${var.vm_id}"
  node_name = "pve"
  vm_id     = var.vm_id
  tags      = var.vm_tags

  # After creating vm do not change it
  lifecycle {
    ignore_changes = [initialization, agent]
  }

  scsi_hardware = "virtio-scsi-single"
  boot_order = local.boot_interfaces

  dynamic "disk" {
    for_each = var.vm_disks
    content {
      datastore_id = disk.value.datastore_id
      size         = disk.value.size
      interface    = disk.value.interface
      file_id      = disk.value.is_boot_disk ? proxmox_download_file.distro_cloud_image.id : null
      serial       = lookup(disk.value, "serial", null)
    }
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.vm_ip}/24"
        gateway = var.vm_ip_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  #Enable QEMU agent
  agent {
    enabled = true
    timeout = "5m"
  }

  cpu {
    cores = var.vm_cpus
    type  = "x86-64-v2-AES" # recommended in bpg/proxmox docs for modern CPUs
  }

  memory {
    dedicated = var.vm_memory_dedicated
    floating  = var.vm_memory_floating
  }
}

resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  upload_mode = "sftp"

  source_raw {
    data = templatefile("${path.module}/cloud-init.tftpl", {
      vm_admin_username    = var.vm_admin_username
      vm_admin_ssh_pub_key = var.vm_admin_ssh_pub_key
    })
    file_name = "cloud-init-${var.vm_id}.yaml"
  }

  # After creating vm do not change it
  lifecycle {
    ignore_changes = [
      source_raw[0].data
    ]
  }
}
