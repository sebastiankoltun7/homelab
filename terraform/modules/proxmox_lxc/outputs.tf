output "template_file_id" {
  value = local.template_file_id
}

output "lxc_id" {
  value = proxmox_virtual_environment_container.lxc_container.id
}