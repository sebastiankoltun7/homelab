.PHONY: help setup ansible-install ansible-all ansible-docker ansible-adguard ansible-dry-run tf-init tf-plan tf-apply tf-destroy docker-context all clean

ANSIBLE_DIR := ansible
TERRAFORM_DIR := terraform
DOCKER_USER := skoltun
DOCKER_HOST_IP := 192.168.1.102

help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ──────────────────────────────────────────────
# Setup
# ──────────────────────────────────────────────

setup: setup-venv ansible-install ## Full local setup (venv + dependencies)
	@echo ""
	@echo "Setup complete. Next steps:"
	@echo "  1. cp terraform/terraform.tfvars.template terraform/terraform.tfvars"
	@echo "  2. Edit terraform/terraform.tfvars with your Proxmox credentials"

setup-venv: ## Create Python virtual environment and install dependencies
	@echo "Creating virtual environment..."
	@cd $(ANSIBLE_DIR) && python3 -m venv .venv
	@echo "Installing Python packages..."
	@cd $(ANSIBLE_DIR) && .venv/bin/pip install --upgrade pip -q
	@cd $(ANSIBLE_DIR) && .venv/bin/pip install paramiko proxmoxer requests -q
	@echo "Python environment ready."

# ──────────────────────────────────────────────
# Ansible
# ──────────────────────────────────────────────

ansible-install: ## Install Ansible collections from requirements.yml
	@echo "Installing Ansible collections..."
	@cd $(ANSIBLE_DIR) && ansible-galaxy install -r requirements.yml --force
	@echo "Collections installed."

ansible-all: ## Run all Ansible playbooks
	@echo "Running all playbooks..."
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/install_adguard.yml
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/install_docker.yml

ansible-docker: ## Deploy Docker host
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/install_docker.yml

ansible-adguard: ## Deploy AdGuard Home
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/install_adguard.yml

ansible-dry-run: ## Dry-run all playbooks (check mode)
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/install_adguard.yml --check
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/install_docker.yml --check

# ──────────────────────────────────────────────
# Terraform
# ──────────────────────────────────────────────

tf-init: ## Initialize Terraform providers and modules
	@cd $(TERRAFORM_DIR) && terraform init

tf-plan: ## Preview infrastructure changes
	@cd $(TERRAFORM_DIR) && terraform plan

tf-apply: ## Apply infrastructure changes
	@cd $(TERRAFORM_DIR) && terraform apply

tf-destroy: ## Destroy all managed infrastructure
	@cd $(TERRAFORM_DIR) && terraform destroy

# ──────────────────────────────────────────────
# Combined
# ──────────────────────────────────────────────

all: tf-init tf-apply ansible-install ansible-all ## Full deployment (Terraform + Ansible)

# ──────────────────────────────────────────────
# Utility
# ──────────────────────────────────────────────

docker-context: ## Create Docker context for remote deployment
	docker context create homelab --docker "host=ssh://$(DOCKER_USER)@$(DOCKER_HOST_IP)"
	docker context use homelab

clean: ## Remove virtual environment
	@rm -rf $(ANSIBLE_DIR)/.venv
	@echo "Virtual environment removed."
