module "adguard_home" {
  source                       = "../proxmox_lxc"
  vm_id                        = var.vm_id
  lxc_name                     = var.name
  tags                         = concat(["managment-plane"], var.tags)
  ip_address                   = var.ip
  template_datastore_id        = "local"
  disk_datastore_id            = "local-lvm"
  cores                        = 1
  memory                       = 512
  disk_size                    = 8
  os_template_source           = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
  user_account_ssh_public_keys = [var.lxc_ssh_pub_key]
}

//Overrides
variable "vm_id" {
  type = number
}
variable "name" {
  type = string
}
variable "tags" {
  type = list(string)
}
variable "ip" {
  type = string
}
variable "lxc_ssh_pub_key" {
  type = string
}
