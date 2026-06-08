output "vm_name" {
  description = "The name of the deployed VM"
  value       = proxmox_virtual_environment_vm.vm_node.name
}

output "vm_id" {
  description = "The VM ID in Proxmox"
  value       = proxmox_virtual_environment_vm.vm_node.vm_id
}

output "vm_ip" {
  description = "The IP address of the VM"
  value       = var.vm_ip
}

output "connection_string" {
  description = "Useful command to connect to the VM"
  value       = "ssh ${var.vm_admin_username}@${var.vm_ip}"
}