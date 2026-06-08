module "basic_vm" {
  source  = "../../modules/proxmox_vm"
  vm_id   = 101
  vm_name = "k3s-node"

  # OS Image
  distro_image_url = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2"

  # Network
  vm_ip         = "192.168.1.101"
  vm_ip_gateway = "192.168.1.1"

  # Resources
  vm_cpus              = 2
  vm_memory_dedicated  = 2048
  vm_memory_floating   = 8192
  vm_disk_size         = 20

  # Admin Access
  vm_admin_username    = "skoltun"
  vm_admin_ssh_pub_key = var.vm_ssh_pub_key
}
