variable "vm_ip" {
  description = "New VM IP address"
  type        = string
}

variable "vm_ip_gateway" {
  description = "Network gateway IP"
  type        = string
  default     = "192.168.1.1"
}

variable "vm_name" {
  description = "VM name"
  type        = string
}

variable "vm_id" {
  description = "Proxmox machine ID (unique)"
  type        = number
}

variable "distro_image_url" {
  type        = string
  description = "Distro image URL"
  default     = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
}

variable "vm_cpus" {
  description = "Number of cpus"
  type        = number
  default     = 2
}

variable "vm_memory_dedicated" {
  description = "Dedicated (exclusive) memory in MB"
  type        = number
  default     = 2048
}

variable "vm_memory_floating" {
  description = "Floating (balooning) memory in MB"
  type        = number
  default     = 8192
}

variable "vm_disk_size" {
  description = "Disk size"
  type        = number
  default     = 20
}

variable "vm_admin_username" {
  type        = string
  description = "VM admin username"
}

variable "vm_admin_ssh_pub_key" {
  type        = string
  description = "VM admin usernam SSH public key added to vm ssh_authorized_keys"
}