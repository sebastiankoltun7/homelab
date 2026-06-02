variable "proxmox_api_token" {
  description = "Token API do Proxmox w formacie użytkownik@pve!token=sekret"
  type        = string
  sensitive   = true
}

variable "password" {
  description = "User password"
  type        = string
  sensitive   = true
}

variable "vm_ip" {
  description = "New machine IP address."
  type        = string
}

variable "vm_ip_gateway" {
  description = "Network gateway IP"
  type        = string
  default     = "192.168.1.1"
}

variable "vm_id" {
  description = "Proxmox machine ID (unique)"
  type        = number
}

variable "distro_image_url" {
  type        = string
  description = "Distro image URL"
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2"
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
    type = number
    default = 20
}