terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://${var.proxmox_ip}:${var.proxmox_port}/"
  username  = var.username
  api_token = var.api_token
  insecure  = true

  ssh {
    agent       = false # dont use local ssh agent
    username    = "root"
    private_key = file(var.root_ssh_pub_key_location)

    node {
      name    = "pve"
      address = var.proxmox_ip
    }
  }
}

# Fetch & unpack distro image
resource "proxmox_download_file" "distro_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = "pve"
  file_name    = replace(basename(var.distro_image_url), ".img", ".qcow2")
  url          = var.distro_image_url
  # After creating vm do not change it after
  overwrite = false
}

resource "proxmox_virtual_environment_vm" "vm_node" {
  name      = "${var.vm_name}-${var.vm_id}"
  node_name = "pve"
  vm_id     = var.vm_id

  # After creating vm do not change it after
  lifecycle {
    ignore_changes = [disk, initialization, agent]
  }

  boot_order = ["scsi0"]

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_download_file.distro_cloud_image.id
    interface    = "scsi0"
    size         = var.vm_disk_size
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
    data = templatefile("cloud-init.tftpl", {
      vm_ssh_pub_key = var.vm_ssh_pub_key
    })
    file_name = "cloud-init.yaml"
  }

  # After creating vm do not change it after
  lifecycle {
    ignore_changes = [
      source_raw[0].data
    ]
  }
}
