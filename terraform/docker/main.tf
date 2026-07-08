module "docker-prod" {
  source  = "../modules/proxmox_vm"
  vm_id   = 101
  vm_name = "docker-prod"
  vm_tags = ["env-prod", "role-docker", "managment-plane"]

  # OS Image
  distro_image_url = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"

  # Network
  vm_ip         = "192.168.1.101"
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
  vm_admin_username    = "skoltun"
  vm_admin_ssh_pub_key = var.vm_ssh_pub_key
}
