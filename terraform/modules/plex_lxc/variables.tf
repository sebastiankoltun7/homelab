variable "id" {
  type        = number
  description = "Proxmox VM ID for the Plex LXC"
}

variable "name" {
  type        = string
  description = "Hostname for the Plex LXC"
}

variable "tags" {
  type        = list(string)
  description = "Additional tags for the Plex LXC"
}

variable "ip" {
  type        = string
  description = "IP address for the Plex LXC"
}

variable "ssh_pub_key" {
  type        = string
  description = "SSH public key for the Plex LXC"
}

variable "template_file_id" {
  type        = string
  description = "Existing OS template file id to reuse (from adguard_lxc)"
}
