module "docker" {
  source = "./modules/docker_vm"
  vm_id = 101
  vm_name = "docker"
  vm_ip = "192.168.1.101"
  vm_admin_username = "skoltun"
  vm_admin_public_key = var.vm_ssh_pub_key
}
