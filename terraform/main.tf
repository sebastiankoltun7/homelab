module "adguard_home" {
  source      = "./modules/adguard_lxc"
  id          = 101
  name        = "adguard"
  tags        = ["role-adguard"]
  ip          = "192.168.1.101"
  ssh_pub_key = var.vm_ssh_pub_key
}

module "docker" {
  source            = "./modules/docker_vm"
  id                = 102
  name              = "docker"
  tags              = ["role-docker"]
  ip                = "192.168.1.102"
  vm_admin_username = "skoltun"
  ssh_pub_key       = var.vm_ssh_pub_key
}
