module "k3s_vm" {
  source  = "../proxmox_vm"
  id      = var.id
  vm_name = var.name
  vm_tags = concat(["k3s-node"], var.tags)

  # OS Image
  distro_image_url = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"

  # Network
  vm_ip           = var.ip
  vm_ip_gateway   = "192.168.1.1"
  enable_firewall = true

  # Resources
  vm_cpus             = 4
  vm_memory_dedicated = 12288
  vm_memory_floating  = 6144

  vm_disks = [
    {
      size         = 10
      datastore_id = "local-lvm"
      interface    = "virtio0"
      is_boot_disk = true
      serial       = "OS-BOOT"
    },
    {
      size         = 60
      datastore_id = "local-lvm"
      interface    = "virtio1"
      is_boot_disk = false
      serial       = "K3s-DATA"
    }
  ]

  # Admin Access
  vm_admin_username    = var.vm_admin_username
  vm_admin_ssh_pub_key = var.ssh_pub_key
}

module "k3s_firewall" {
  source    = "../proxmox_firewall"
  vm_id     = var.id
  node_name = "pve"

  # Inbound traffic entering the K3s VM
  inbound_rules = [
    {
      port    = "22"
      source  = "192.168.1.0/24"
      comment = "Allow SSH from local network"
    },
    {
      port    = "6443"
      proto   = "tcp"
      source  = "192.168.1.0/24"
      comment = "Allow Kubernetes API server access"
    },
    {
      port    = "10250"
      proto   = "tcp"
      source  = "192.168.1.0/24"
      comment = "Allow Kubelet metrics/API"
    },
    {
      port    = "8472"
      proto   = "udp"
      comment = "Allow Flannel VXLAN overlay networking"
    },
    {
      port    = "80"
      proto   = "tcp"
      comment = "Allow HTTP inbound for Traefik Ingress"
    },
    {
      port    = "443"
      proto   = "tcp"
      comment = "Allow HTTPS inbound for Traefik Ingress and TLS"
    }
  ]

  # Outbound traffic leaving the K3s VM
  outbound_rules = [
    # ALLOW: DNS queries to your AdGuard container
    {
      port    = "53"
      proto   = "udp"
      dest    = "192.168.1.101"
      comment = "Allow DNS queries to AdGuard"
    },
    {
      port    = "53"
      proto   = "tcp"
      dest    = "192.168.1.101"
      comment = "Allow DNS queries to AdGuard (TCP)"
    },
    # DROP local network access (except explicit needs above)
    {
      dest    = "192.168.0.0/16"
      action  = "DROP"
      comment = "Block local subnet"
      log     = "info"
    },
    {
      dest    = "10.0.0.0/8"
      action  = "DROP"
      comment = "Block private Class A networks"
      log     = "info"
    },
    {
      dest    = "172.16.0.0/12"
      action  = "DROP"
      comment = "Block private Class B networks"
      log     = "info"
    }
  ]
}

// Overrides
variable "id" {
  type = number
}
variable "name" {
  type = string
}
variable "ip" {
  type = string
}
variable "tags" {
  type = list(string)
}
variable "vm_admin_username" {
  type = string
}
variable "ssh_pub_key" {
  type = string
}