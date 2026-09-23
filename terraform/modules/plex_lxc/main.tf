module "plex_lxc" {
  source   = "../proxmox_lxc"
  id       = var.id
  lxc_name = var.name
  tags     = concat(["media-plane"], var.tags)

  # Network
  ip_address       = var.ip
  ip_gateway       = "192.168.1.1"
  network_firewall = true

  # Resources
  cores             = 2
  memory            = 512
  swap              = 512
  disk_datastore_id = "local-lvm"
  disk_size         = 8

  # Startup behaviour
  startup_order = 2

  # Template (shared with adguard, no re-download)
  template_file_id   = var.template_file_id
  os_template_source = "" # unused when template_file_id is set
  os_template_type   = "debian"

  # Bind mounts to the external USB SSD.
  # Applied by the Ansible "setup_pve_host" playbook (`pct set`) because
  # Proxmox only allows bind mounts for root@pam, not an API token.
  apply_mount_points = false
  mount_points       = [
    {
      volume = "/mnt/pve/ssd-backup/PlexMedia"
      path   = "/PlexMedia"
    },
    {
      volume = "/mnt/pve/ssd-backup/PlexConfig"
      path   = "/plex-config"
    }
  ]

  # GPU passthrough for hardware transcoding.
  # Configured out-of-band (Ansible `setup_pve_dri` playbook) because Proxmox
  # only allows device passthrough for root@pam, not the Terraform API token.
  # device_passthrough = [...]

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
variable "template_file_id" {
  type = string
}