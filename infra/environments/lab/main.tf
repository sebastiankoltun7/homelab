terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.1.100:8006/"
  password = var.password
  username = "root@pam"
  insecure = true

  ssh {
    agent    = true
    username = "root"

    node {
      name    = "pve"
      address = "192.168.1.100"
    }
  }
}

resource "proxmox_download_file" "distro_cloud_image" {
  #   content_type = "import"
  #   datastore_id = "local"
  #   node_name    = "pve"
  #   url          = var.distro_image_url
  content_type = "import"
  datastore_id = "local"
  file_name    = "jammy-server-cloudimg-amd64.qcow2"
  node_name    = "pve"
  url          = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  overwrite    = true
}

resource "proxmox_virtual_environment_vm" "k3s_node" {
  name      = "k3s-node-${var.vm_id}"
  node_name = "pve"
  vm_id     = var.vm_id

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

  serial_device {}
  vga {
    type = "serial0"
  }

  cpu {
    cores = var.vm_cpus
    type  = "x86-64-v2-AES" # recommended for modern CPUs
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
    data      = file("cloud-init.yaml")
    file_name = "cloud-init.yaml"
  }
}
