module "adguard_home" {
  source          = "./modules/adguard_home"
  vm_id           = 101
  name            = "adguard"
  tags            = ["role-adguard"]
  ip              = "192.168.1.101"
  lxc_ssh_pub_key = var.vm_ssh_pub_key
}

module "docker" {
  source              = "./modules/docker_vm"
  vm_id               = 102
  vm_name             = "docker"
  tags                = ["role-docker"]
  vm_ip               = "192.168.1.102"
  vm_admin_username   = "skoltun"
  vm_admin_public_key = var.vm_ssh_pub_key
}
