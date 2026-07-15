.PHONY: help setup clean all \
       tf-init tf-plan tf-apply tf-destroy \
       ansible-install ansible-all ansible-adguard ansible-docker ansible-dry-run \
       vault-create terraform-tfvars docker-context ssh-accept-keys ssh-cleanup

ANSIBLE_DIR := ansible
TERRAFORM_DIR := terraform
DOCKER_USER := skoltun
DOCKER_HOST_IP := 192.168.1.102
ANSIBLE_PLAYBOOK = cd $(ANSIBLE_DIR) && ansible-playbook

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
	@cd $(ANSIBLE_DIR) && .venv/bin/pip install paramiko proxmoxer requests -q

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
	@cd $(ANSIBLE_DIR) && ansible-galaxy install -r requirements.yml --force

ansible-all: ssh-accept-keys ## Run all playbooks
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml

ansible-adguard: ssh-accept-keys ## Deploy AdGuard Home
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml

ansible-docker: ssh-accept-keys ## Deploy Docker host
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml

ansible-dry-run: ## Dry-run all playbooks
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml --check
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml --check

# ── Combined ───────────────────────────────────

all: tf-init tf-apply ansible-install ssh-cleanup ansible-all ## Full deployment (Terraform + Ansible)

# ── Utility ────────────────────────────────────

ssh-cleanup: ## Remove stale SSH host keys for homelab hosts
	@ssh-keygen -R $(DOCKER_HOST_IP) 2>/dev/null || true

ssh-accept-keys: ## Accept SSH host keys
	@ssh-keyscan -H $(DOCKER_HOST_IP) >> ~/.ssh/known_hosts 2>/dev/null || true

docker-context: ssh-accept-keys ## Setup remote Docker context
	@docker context create homelab --docker "host=ssh://$(DOCKER_USER)@$(DOCKER_HOST_IP)"
	@docker context use homelab

clean: ## Remove venv
	@rm -rf $(ANSIBLE_DIR)/.venv
