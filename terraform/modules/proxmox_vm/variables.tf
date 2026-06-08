variable "vm_ip" {
  description = "New VM IP address"
  type        = string
  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.vm_ip))
    error_message = "The vm_ip must be a valid IPv4 address (e.g., 192.168.1.100)."
  }
}

variable "vm_ip_gateway" {
  description = "Network gateway IP"
  type        = string
  default     = "192.168.1.1"
  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.vm_ip_gateway))
    error_message = "The vm_ip_gateway must be a valid IPv4 address."
  }
}

variable "vm_name" {
  description = "VM name"
  type        = string
  validation {
    condition     = length(var.vm_name) >= 3
    error_message = "The vm_name must be at least 3 characters long."
  }
}

variable "vm_id" {
  description = "Proxmox machine ID (unique)"
  type        = number
  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999
    error_message = "The vm_id must be between 100 and 999999."
  }
}

variable "vm_tags" {
  type        = set(string)
  description = "VM tags"
  default     = []
}

variable "distro_image_url" {
  type        = string
  description = "Distro image URL"
  default     = "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
  validation {
    condition     = can(regex("^https?://", var.distro_image_url))
    error_message = "The distro_image_url must be a valid HTTP or HTTPS URL."
  }
}

variable "vm_cpus" {
  description = "Number of CPUs"
  type        = number
  default     = 2
  validation {
    condition     = var.vm_cpus >= 1 && var.vm_cpus <= 64
    error_message = "Number of CPUs must be between 1 and 64."
  }
}

variable "vm_memory_dedicated" {
  description = "Dedicated (exclusive) memory in MB"
  type        = number
  default     = 2048
  validation {
    condition     = var.vm_memory_dedicated >= 512
    error_message = "Dedicated memory must be at least 512 MB."
  }
}

variable "vm_memory_floating" {
  description = "Floating (ballooning) memory in MB"
  type        = number
  default     = 8192
  validation {
    condition     = var.vm_memory_floating >= 512
    error_message = "Floating memory must be at least 512 MB."
  }
}

variable "vm_disks" {
  type = list(object({
    size         = number
    datastore_id = string
    interface    = string
    is_boot_disk = bool
    serial       = optional(string)
  }))

  validation {
    condition     = length([for d in var.vm_disks : d if d.is_boot_disk]) == 1
    error_message = "The VM must have exactly one disk configured as the boot disk (is_boot_disk = true)."
  }

  validation {
    condition     = alltrue([for d in var.vm_disks : d.size >= 1])
    error_message = "Each disk must have a size of at least 1 GB."
  }
}

variable "vm_admin_username" {
  type        = string
  description = "VM admin username"
  validation {
    condition     = length(var.vm_admin_username) >= 3
    error_message = "The username must be at least 3 characters long."
  }
}

variable "vm_admin_ssh_pub_key" {
  type        = string
  description = "VM admin SSH public key"
  validation {
    condition     = can(regex("^ssh-", var.vm_admin_ssh_pub_key))
    error_message = "The SSH key must start with 'ssh-'."
  }
}