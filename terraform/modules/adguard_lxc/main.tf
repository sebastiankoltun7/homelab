module "adguard_lxc" {
  source                       = "../proxmox_lxc"
  id                           = var.id
  lxc_name                     = var.name
  tags                         = concat(["managment-plane"], var.tags)

  # Network
  ip_address                   = var.ip
  ip_gateway                   = "192.168.1.1"

  # Resources
  disk_datastore_id            = "local-lvm"
  cores                        = 1
  memory                       = 512
  disk_size                    = 8

  # Template
  template_datastore_id        = "local"
  os_template_source           = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"

  # Admin Access
  user_account_ssh_public_keys = [var.ssh_pub_key]
}

//Overrides
variable "id" {
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
variable "ssh_pub_key" {
  type = string
}
