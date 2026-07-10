variable "vm_id" {
  type        = number
  description = "Proxmox VM ID"
}

variable "template_datastore_id" {
  type        = string
  default     = "local"
  description = "Proxmox template datastore id ex: local"
}

variable "os_template_source" {
  type        = string
  description = "OS template download link"
}

variable "tags" {
  type = list(string)
}

variable "memory" {
  type        = number
  description = "LXC container memory"
}

variable "cores" {
  type        = number
  description = "LXC container core count"
}

variable "lxc_name" {
  type        = string
  description = "LXC container hostname"
}

variable "user_account_ssh_public_keys" {
  type        = list(string)
  description = "List of SSH public keys to add on LXC container"
  default     = []
}

variable "ip_address" {
  type        = string
  description = "LXC container IP address"
}

variable "gateway_ip" {
  type        = string
  default     = "192.168.1.1"
  description = "LXC container IP gateway"
}

variable "disk_datastore_id" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox disk name. ex: local-lvm"
}

variable "disk_size" {
  type = number
}
