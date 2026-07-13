.PHONY: help setup clean all \
       tf-init tf-plan tf-apply tf-destroy \
       ansible-install ansible-all ansible-adguard ansible-docker ansible-dry-run \
       vault-create docker-context ssh-accept-keys

ANSIBLE_DIR := ansible
TERRAFORM_DIR := terraform
DOCKER_USER := skoltun
DOCKER_HOST_IP := 192.168.1.102
ANSIBLE_PLAYBOOK = cd $(ANSIBLE_DIR) && ansible-playbook

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Setup ──────────────────────────────────────

setup: setup-venv ansible-install vault-create ## Full local setup
	@echo "Done. Edit vault.yml and terraform.tfvars, then run 'make all'."

setup-venv: ## Create venv and install dependencies
	@cd $(ANSIBLE_DIR) && python3 -m venv .venv
	@cd $(ANSIBLE_DIR) && .venv/bin/pip install --upgrade pip -q
	@cd $(ANSIBLE_DIR) && .venv/bin/pip install paramiko proxmoxer requests -q

vault-create: ## Create vault.yml from template (skip if exists)
	@test -f $(ANSIBLE_DIR)/group_vars/all/vault.yml && echo "vault.yml exists, skipping." || \
		(cp $(ANSIBLE_DIR)/vault.yml.template $(ANSIBLE_DIR)/group_vars/all/vault.yml && echo "Created vault.yml")

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

ansible-all: ## Run all playbooks
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml

ansible-adguard: ## Deploy AdGuard Home
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml

ansible-docker: ## Deploy Docker host
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml

ansible-dry-run: ## Dry-run all playbooks
	$(ANSIBLE_PLAYBOOK) playbooks/install_adguard.yml --check
	$(ANSIBLE_PLAYBOOK) playbooks/install_docker.yml --check

# ── Combined ───────────────────────────────────

all: tf-init tf-apply ansible-install ansible-all ## Full deployment (Terraform + Ansible)

# ── Utility ────────────────────────────────────

ssh-accept-keys: ## Accept SSH host keys
	@ssh-keyscan -H $(DOCKER_HOST_IP) >> ~/.ssh/known_hosts 2>/dev/null || true

docker-context: ssh-accept-keys ## Setup remote Docker context
	@docker context create homelab --docker "host=ssh://$(DOCKER_USER)@$(DOCKER_HOST_IP)"
	@docker context use homelab

clean: ## Remove venv
	@rm -rf $(ANSIBLE_DIR)/.venv
