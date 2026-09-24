terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.108.0"
    }
  }
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  container_id = var.container_id
  vm_id        = var.vm_id
  node_name    = var.node_name

  # Inbound rules
  dynamic "rule" {
    for_each = var.inbound_rules
    content {
      type    = "in"
      action  = "ACCEPT"
      proto   = rule.value.proto
      dport   = rule.value.port
      source  = lookup(rule.value, "source", null)
      iface   = "net0"
      comment = lookup(rule.value, "comment", null)
      log     = lookup(rule.value, "log", null)
    }
  }

  # Outbound rules
  dynamic "rule" {
    for_each = var.outbound_rules
    content {
      type    = "out"
      action  = rule.value.action
      proto   = rule.value.proto
      dport   = lookup(rule.value, "port", null)
      dest    = lookup(rule.value, "dest", null)
      iface   = "net0"
      comment = lookup(rule.value, "comment", null)
      log     = lookup(rule.value, "log", null)
    }
  }
}

variable "container_id" {
  type    = number
  default = null
}

variable "vm_id" {
  type    = number
  default = null
}

variable "node_name" {
  type        = string
  description = "The Proxmox host node name"
}

variable "inbound_rules" {
  type = list(object({
    port    = string
    proto   = optional(string, "tcp")
    source  = optional(string)
    comment = optional(string)
    log     = optional(string)
  }))
  default     = []
}

variable "outbound_rules" {
  type = list(object({
    port    = optional(string)
    dest    = optional(string)
    proto   = optional(string)
    action  = optional(string, "ACCEPT")
    comment = optional(string)
    log     = optional(string)
  }))
  default     = []
}