.PHONY: help setup clean all \
        tf-init tf-plan tf-apply tf-destroy \
        ansible-install ansible-all ansible-adguard ansible-docker ansible-plex ansible-k3s ansible-pve ansible-pve-host ansible-dry-run \
        vault-create terraform-tfvars docker-context ssh-accept-keys ssh-cleanup kubectl-install kubectl-config kubectl-setup

ANSIBLE_DIR := ansible
TERRAFORM_DIR := terraform
DOCKER_USER ?= skoltun
DOCKER_HOST_IP := 192.168.1.102
PROXMOX_HOST_IP := 192.168.1.100
K3S_HOST_IP := 192.168.1.104
KUBECONFIG_SRC := ansible/playbooks/files/k3s.yaml
ANSIBLE_PLAYBOOK = cd $(ANSIBLE_DIR) && ansible-playbook
ANSIBLE_GALAXY = cd $(ANSIBLE_DIR) && ansible-galaxy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Setup ──────────────────────────────────────

setup: setup-venv ansible-install vault-create terraform-tfvars ## Full local setup
	@echo ""
	@echo "Setup complete. Edit the following files with your values:"
	@echo "  - terraform/terraform.tfvars  (Proxmox credentials)"
	@echo "  - ansible/group_vars/all/vault.yml  (secrets)"
	@echo ""
	@echo "Then run 'make all'."

setup-venv: ## Create venv and install dependencies
	@cd $(ANSIBLE_DIR) && python3 -m venv .venv
	@cd $(ANSIBLE_DIR) && .venv/bin/pip install --upgrade pip -q
	@cd $(ANSIBLE_DIR) && .venv/bin/pip install ansible-core paramiko proxmoxer requests -q
	@echo "Activate with: source ansible/.venv/bin/activate"

vault-create: ## Create vault.yml from template (skip if exists)
	@test -f $(ANSIBLE_DIR)/group_vars/all/vault.yml && echo "vault.yml exists, skipping." || \
		(cp $(ANSIBLE_DIR)/vault.yml.template $(ANSIBLE_DIR)/group_vars/all/vault.yml && echo "Created vault.yml")

terraform-tfvars: ## Create terraform.tfvars from template (skip if exists)
	@test -f $(TERRAFORM_DIR)/terraform.tfvars && echo "terraform.tfvars exists, skipping." || \
		(cp $(TERRAFORM_DIR)/terraform.tfvars.template $(TERRAFORM_DIR)/terraform.tfvars && echo "Created terraform.tfvars")

# ── Terraform ──────────────────────────────────

tf-init: ## Initialize Terraform
	@cd $(TERRAFORM_DIR) && terraform init

tf-plan: ## Preview infrastructure changes
	@cd $(TERRAFORM_DIR) && terraform plan

tf-apply: ## Apply infrastructure changes
	@cd $(TERRAFORM_DIR) && terraform apply

tf-destroy: ## Destroy all infrastructure
	@cd $(TERRAFORM_DIR) && terraform destroy

# ── Ansible ────────────────────────────────────

ansible-install: ## Install Ansible collections
	@if [ -x $(ANSIBLE_DIR)/.venv/bin/ansible-galaxy ]; then \
		$(ANSIBLE_DIR)/.venv/bin/ansible-galaxy install -r $(ANSIBLE_DIR)/requirements.yml --force; \
	else \
		$(ANSIBLE_GALAXY) install -r requirements.yml --force; \
	fi

ansible-all: ssh-accept-keys ## Run all playbooks (adguard + docker + plex + k3s)
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml
	$(ANSIBLE_PLAYBOOK) playbooks/install_plex.yml
	$(ANSIBLE_PLAYBOOK) playbooks/install_k3s.yml

ansible-adguard: ssh-accept-keys ## Deploy AdGuard Home
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml

ansible-docker: ssh-accept-keys ## Deploy Docker host
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml

ansible-plex: ssh-accept-keys ## Deploy Plex Media Server
	$(ANSIBLE_PLAYBOOK) playbooks/install_plex.yml

ansible-k3s: ssh-accept-keys ## Deploy K3s single-node (192.168.1.104)
	$(ANSIBLE_PLAYBOOK) playbooks/install_k3s.yml

ansible-pve: ## Mount external disks on the Proxmox host
	$(ANSIBLE_PLAYBOOK) playbooks/setup_pve_storage.yml

ansible-pve-host: ## Configure Proxmox host for the plex LXC (binds + GPU, root@pam)
	$(ANSIBLE_PLAYBOOK) playbooks/setup_pve_host.yml

ansible-dry-run: ## Dry-run all playbooks
	$(ANSIBLE_PLAYBOOK) playbooks/setup_pve_storage.yml --check
	$(ANSIBLE_PLAYBOOK) playbooks/setup_pve_host.yml --check
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml --check
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml --check
	$(ANSIBLE_PLAYBOOK) playbooks/install_plex.yml --check
	$(ANSIBLE_PLAYBOOK) playbooks/install_k3s.yml --check

# ── Combined ───────────────────────────────────

all: ansible-install ssh-cleanup ansible-pve tf-init tf-apply ansible-pve-host ansible-all ## Full deployment (mount disks, Terraform + Ansible)

# ── Utility ────────────────────────────────────

ssh-cleanup: ## Remove stale SSH host keys for homelab hosts (.100, .102, .104)
	@ssh-keygen -R $(DOCKER_HOST_IP) 2>/dev/null || true
	@ssh-keygen -R $(PROXMOX_HOST_IP) 2>/dev/null || true
	@ssh-keygen -R $(K3S_HOST_IP) 2>/dev/null || true

ssh-accept-keys: ## Accept SSH host keys (.100, .102, .104)
	@ssh-keyscan -H $(DOCKER_HOST_IP) >> ~/.ssh/known_hosts 2>/dev/null || true
	@ssh-keyscan -H $(PROXMOX_HOST_IP) >> ~/.ssh/known_hosts 2>/dev/null || true
	@ssh-keyscan -H $(K3S_HOST_IP) >> ~/.ssh/known_hosts 2>/dev/null || true

docker-context: ssh-accept-keys ## Setup remote Docker context
	@docker context create homelab --docker "host=ssh://$(DOCKER_USER)@$(DOCKER_HOST_IP)"
	@docker context use homelab

# ── K3s / kubectl ────────────────────────────────

kubectl-install: ## Install kubectl (Linux amd64, stable)
	@curl -LO "https://dl.k8s.io/release/$$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
	@chmod +x kubectl
	@sudo mv kubectl /usr/local/bin/kubectl
	@kubectl version --client

kubectl-config: ## Configure kubeconfig from fetched k3s.yaml (127.0.0.1 -> 192.168.1.104)
	@test -f $(KUBECONFIG_SRC) || (echo "Missing $(KUBECONFIG_SRC). Run 'make ansible-k3s' first." && exit 1)
	@sed -i 's/127\.0\.0\.1/$(K3S_HOST_IP)/g' $(KUBECONFIG_SRC)
	@mkdir -p ~/.kube
	@cp $(KUBECONFIG_SRC) ~/.kube/config
	@chmod 600 ~/.kube/config
	@echo "Kubeconfig installed to ~/.kube/config (server https://$(K3S_HOST_IP):6443)"
	@kubectl get nodes || (echo "kubectl get nodes failed - check K3s is Ready (kubectl get nodes)" && exit 1)

kubectl-setup: kubectl-install kubectl-config ## Full local kubectl setup (install + kubeconfig, opt-in)
	@echo "kubectl ready. Try: kubectl cluster-info && kubectl get pods -A"

clean: ## Remove venv
	@rm -rf $(ANSIBLE_DIR)/.venv
