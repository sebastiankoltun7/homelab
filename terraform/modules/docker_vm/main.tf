//Composite module
module "docker_vm" {
  source  = "../proxmox_vm"
  id      = var.id
  vm_name = var.name
  vm_tags = concat(["managment-plane"], var.tags)

  # OS Image
  distro_image_url = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"

  # Network
  vm_ip         = var.ip
  vm_ip_gateway = "192.168.1.1"

  # Resources
  vm_cpus             = 2
  vm_memory_dedicated = 2048
  vm_memory_floating  = 8192

  vm_disks = [
    {
      size         = 10
      datastore_id = "local-lvm"
      interface    = "virtio0"
      is_boot_disk = true
      serial       = "OS-BOOT"
    },
    {
      size         = 50
      datastore_id = "local-lvm"
      interface    = "virtio1"
      is_boot_disk = false
      serial       = "DOCKER-DATA"
    }
  ]

  # Admin Access
  vm_admin_username    = var.vm_admin_username
  vm_admin_ssh_pub_key = var.ssh_pub_key
}

//Overrides
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
