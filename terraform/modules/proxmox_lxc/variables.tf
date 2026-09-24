variable "id" {
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
  default     = ""
  description = "OS template download link (ignored when template_file_id is set)"
}

variable "tags" {
  type = list(string)
}

variable "memory" {
  type        = number
  description = "LXC container memory in MB"
}

variable "swap" {
  type        = number
  default     = 0
  description = "LXC container swap size in MB"
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

variable "ip_gateway" {
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

variable "os_template_type" {
  type = string
}

variable "enable_firewall" {
  type        = bool
  default     = false
  description = "Enable firewall rules on the container network interface"
}

variable "startup_order" {
  type        = number
  default     = null
  description = "Startup order of the container (null disables the startup block)"
}

variable "device_passthrough" {
  type = list(object({
    path = string
  }))
  default     = []
  description = "Devices to pass through to the container"
}

variable "template_file_id" {
  type        = string
  default     = null
  description = "Existing OS template file id to reuse instead of downloading a new one"
}