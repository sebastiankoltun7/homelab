module "adguard_lxc" {
  source                       = "./modules/proxmox_lxc"
  vm_id                        = 101
  lxc_name                     = "adguard"
  ip_address                   = "192.168.1.101"
  template_datastore_id        = "local"
  disk_datastore_id            = "local-lvm"
  cores                        = 1
  memory                       = 512
  disk_size                    = 8
  os_template_source           = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
  user_account_ssh_public_keys = [var.vm_ssh_pub_key]
}

module "docker" {
  source              = "./modules/docker_vm"
  vm_id               = 102
  vm_name             = "docker"
  vm_ip               = "192.168.1.102"
  vm_admin_username   = "skoltun"
  vm_admin_public_key = var.vm_ssh_pub_key
}
