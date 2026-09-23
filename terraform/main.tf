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
  vm_admin_username = var.admin_username
  ssh_pub_key       = var.vm_ssh_pub_key
}

module "plex" {
  source           = "./modules/plex_lxc"
  id               = 103
  name             = "plex"
  tags             = ["role-plex"]
  ip               = "192.168.1.103"
  ssh_pub_key      = var.vm_ssh_pub_key
  template_file_id = module.adguard_home.lxc_template_file_id
}
