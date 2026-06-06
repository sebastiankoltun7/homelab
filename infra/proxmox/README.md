# Proxmox VM Deployment with Terraform

This project enables fully automated deployment of virtual machines (VMs) on a **Proxmox VE** server using **Cloud-Init** and the **Terraform** provider (`bpg/proxmox`).

The script automatically downloads the specified distribution image (defaulting to Ubuntu 24.04 LTS Noble Numbat), configures the network, uploads user configuration snippets, and boots the ready-to-use virtual machine.

---

## 🛠️ Prerequisites and Proxmox Preparation

Before running the script, you must properly configure privileges and SSH access within your Proxmox web interface.

### Step 1: Creating a User and Permissions
1. Log in to the Proxmox WebUI as `root@pam`.
2. Navigate to **Datacenter** -> **Permissions** -> **Users** and click **Add**.
   * **User name:** `terraform`
   * **Realm:** `pve`
3. Go to the **Permissions** tab and grant the user an appropriate role on the path `/` (the entire cluster), containing the following privileges: 
   * `PVEAdmin`
   * `Sys.Modify`, `Sys.Audit`
   * `Datastore.Allocate`, `Datastore.AllocateSpace`

### Step 2: Generating an API Token
1. In the WebUI, navigate to **Datacenter** -> **Permissions** -> **API Tokens** and click **Add**.
   * **User:** `terraform@pve`
   * **Token ID:** `terraform-token`
   * *Optional:* Uncheck *Privilege Separation*.
2. Copy the generated **Token Secret** and **Token ID** – they will be required for the `terraform.tfvars` file.

### Step 3: SSH Key and Storage Permissions (Required for SFTP/Cloud-Init)
The Terraform provider requires direct SSH access to the Proxmox host to upload Cloud-Init configuration files to the `snippets` directory.
1. Ensure that your local **public key** is added to the Proxmox host in the `/root/.ssh/authorized_keys` file.
2. Provide the path to your local **private key** (e.g., `~/.ssh/id_ed25519` or `C:/Users/user/.ssh/id_rsa`) in the Terraform configuration.
3. **Important for Snippets:** If you are using a specific storage for your snippets (for example, the default `local` storage), make sure that **Snippets** are enabled in its content types. Navigate to **Datacenter** -> **Storage** -> select your storage (e.g., `local`) -> click **Edit**, and ensure **Snippets** is selected in the **Content** dropdown list.

---

## 🚀 Quick Start (Deployment)

Create your own variables file based on the template:
   ```bash
   cp terraform.tfvars.template terraform.tfvars
terraform plan
terraform apply -auto-approve