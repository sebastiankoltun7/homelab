//Composite module
module "docker_vm" {
  source  = "../proxmox_vm"
  vm_id   = var.vm_id
  vm_name = var.vm_name
  vm_tags = ["env-prod", "role-docker", "managment-plane"]

  # OS Image
  distro_image_url = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"

  # Network
  vm_ip         = var.vm_ip
  vm_ip_gateway = "192.168.1.1"

  # Resources
  vm_cpus              = 2
  vm_memory_dedicated  = 2048
  vm_memory_floating   = 8192

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
  vm_admin_ssh_pub_key = var.vm_admin_public_key
}

//Overrides
variable "vm_id" {
    type = number
}
variable "vm_name" {
  type = string
}
variable "vm_ip" {
  type = string
}
variable "vm_admin_username" {
  type = string
}
variable "vm_admin_public_key" {
  type = string
}
