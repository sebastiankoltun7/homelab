variable "proxmox" {
  type = object({
    ip                 = string
    port               = string
    username           = string
    api_token          = string
    root_ssh_key_location   = string
  })
  sensitive = true
  description = "Proxmox access configuration"
}

variable "vm_ssh_pub_key" {
  type        = string
  description = "SSH public key added to vm ssh_authorized_keys"
}

variable "admin_username" {
  type        = string
  description = "Admin username for VMs and services"
}
