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

module "k3s" {
  source            = "./modules/k3s_vm"
  id                = 104
  name              = "k3s"
  tags              = ["role-k3s"]
  ip                = "192.168.1.104"
  vm_admin_username = var.admin_username
  ssh_pub_key       = var.vm_ssh_pub_key
}

# Enable firewall
resource "proxmox_virtual_environment_cluster_firewall" "this" {
  enabled = true
}

# For LXC Containers (AdGuard & Plex)
resource "proxmox_virtual_environment_firewall_options" "container_options" {
  for_each = toset(["102", "103"])

  node_name    = "pve"
  container_id = tonumber(each.key)

  enabled       = true
  log_level_in  = "info"
  log_level_out = "info"
}

# For VMs (Docker)
resource "proxmox_virtual_environment_firewall_options" "vm_options" {
  for_each = toset(["101"])

  node_name = "pve"
  vm_id     = tonumber(each.key)

  enabled       = true
  log_level_in  = "info"
  log_level_out = "info"
}