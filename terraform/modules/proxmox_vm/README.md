# Terraform Proxmox VM Module

This project provides a robust, production-ready module to automate Proxmox VM lifecycle management using the modern `bpg/proxmox` provider.

## 🚀 Key Features

* **Automated Image Management:** Automatically pulls cloud images (e.g., Ubuntu 24.04 LTS) to Proxmox storage.
* **Dynamic Cloud-Init:** Generates and uploads `cloud-init` configuration files via SFTP/SSH, ensuring your VMs are ready for use immediately after booting.
* **Production-Grade Storage:** Uses `virtio-scsi-single` controllers for optimal I/O performance and better integration with Linux guests.
* **Strict Validation:** Includes robust input validation (IP formats, disk counts, SSH keys) to catch configuration errors during `terraform plan`.
* **Zero-Touch Access:** Injects your public SSH key for passwordless access, with `qemu-guest-agent` configured automatically for better host-guest communication.

---

## 🛠️ Prerequisites and Setup

### 1. Proxmox Permissions
1. **Create a User:** Create a user `terraform@pve` in your Proxmox WebUI.
2. **Assign Roles:** Grant the user the `PVEAdmin` role at the `/` (datacenter) level, or provide specific privileges: `Sys.Modify`, `Sys.Audit`, `Datastore.Allocate`, `Datastore.AllocateSpace`, `VM.Config.Network`, `VM.Config.Disk`, `VM.Allocate`.
3. **API Token:** Generate an API Token under **Permissions** -> **API Tokens** for the `terraform` user. Copy the **Token Secret** and **Token ID**.

### 2. SSH & Snippets Storage
* **SSH Access:** The provider requires SSH access to the Proxmox host. Ensure your local public key is in `/root/.ssh/authorized_keys` on the Proxmox host.
* **Snippets Storage:** Navigate to **Datacenter** -> **Storage** -> `local` (or your chosen storage). Ensure **Snippets** is enabled in the **Content** types. Without this, Cloud-Init will fail.

---

## 💻 Usage Example

In your environment file (e.g., `environments/prod/main.tf`):

```hcl
module "docker_vm" {
  source               = "../../modules/proxmox_vm"
  vm_id                = 101
  vm_name              = "docker-host"
  vm_ip                = "192.168.1.101"
  vm_admin_username    = "youruser"
  vm_admin_ssh_pub_key = "ssh-ed25519 AAAAC3Nza..."

  vm_disks = [
    {
      size         = 10
      datastore_id = "local-lvm"
      interface    = "virtio0"
      is_boot_disk = true
    },
    {
      size         = 50
      datastore_id = "local-lvm"
      interface    = "virtio1"
      is_boot_disk = false
      serial       = "DOCKER-DATA"
    }
  ]
}