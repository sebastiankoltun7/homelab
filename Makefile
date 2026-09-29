.PHONY: help setup tools setup-venv clean all \
        tf-init tf-plan tf-apply tf-destroy \
        ansible-install ansible-all ansible-adguard ansible-docker ansible-plex ansible-k3s ansible-pve ansible-pve-host ansible-dry-run \
        vault-create terraform-tfvars docker-context ssh-accept-keys ssh-cleanup \
        kubectl-config helm-diff \
        apps apps-diff apps-list apps-destroy \
        headlamp-token monitoring-password

ANSIBLE_DIR := ansible
TERRAFORM_DIR := terraform
DOCKER_USER ?= skoltun
DOCKER_HOST_IP := 192.168.1.102
PROXMOX_HOST_IP := 192.168.1.100
K3S_HOST_IP := 192.168.1.104
KUBECONFIG_SRC := ansible/playbooks/files/k3s.yaml
HELM_DIFF_KEYRING := keys/helm-diff.gpg
ANSIBLE_PLAYBOOK = cd $(ANSIBLE_DIR) && ansible-playbook
ANSIBLE_GALAXY = cd $(ANSIBLE_DIR) && ansible-galaxy

# The CLI toolchain is pinned in .mise.toml, so the Makefile resolves every one of
# these through `mise exec` rather than trusting whatever happens to be on PATH.
# That makes the pinned versions the only ones used, in a login shell or in CI.
# The fallback covers shells that never run `mise activate` (non-interactive
# shells, editors, CI), which is exactly where a bare `mise` would not resolve.
MISE := $(or $(shell command -v mise 2>/dev/null),$(HOME)/.local/bin/mise)
mise_run = $(MISE) exec -- $(1)
KUBECTL := $(call mise_run,kubectl)
HELM := $(call mise_run,helm)
HELMFILE := $(call mise_run,helmfile)
TERRAFORM := $(call mise_run,terraform)
PYTHON := $(call mise_run,python)


help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ── Setup ──────────────────────────────────────

setup: tools setup-venv ansible-install vault-create terraform-tfvars ## Full local setup
	@echo ""
	@echo "Setup complete. Edit the following files with your values:"
	@echo "  - terraform/terraform.tfvars  (Proxmox credentials)"
	@echo "  - ansible/group_vars/all/vault.yml  (secrets)"
	@echo ""
	@echo "Then run 'make all', followed by 'make kubectl-config' and 'make helm-diff'."

tools: ## Install the toolchain pinned in .mise.toml
	@command -v $(MISE) >/dev/null 2>&1 || { echo "mise not found at '$(MISE)'. Install it from https://mise.jdx.dev/getting-started.html"; exit 1; }
	@$(MISE) install
	@$(TERRAFORM) version | head -1
	@$(KUBECTL) version --client | head -1
	@$(HELM) version --short
	@$(HELMFILE) --version

setup-venv: ## Create ansible/.venv from the pinned Python and install dependencies
	@cd $(ANSIBLE_DIR) && $(PYTHON) -m venv .venv
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
	@cd $(TERRAFORM_DIR) && $(TERRAFORM) init

tf-plan: ## Preview infrastructure changes
	@cd $(TERRAFORM_DIR) && $(TERRAFORM) plan

tf-apply: ## Apply infrastructure changes
	@cd $(TERRAFORM_DIR) && $(TERRAFORM) apply

tf-destroy: ## Destroy all infrastructure
	@cd $(TERRAFORM_DIR) && $(TERRAFORM) destroy

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

# ── K3s / helm / helmfile ───────────────────────
#
# The binaries come from .mise.toml (`make tools`). What is left to do is local
# wiring: the kubeconfig, and the helm-diff plugin helmfile needs.

kubectl-config: ## Configure kubeconfig from fetched k3s.yaml (127.0.0.1 -> 192.168.1.104)
	@test -f $(KUBECONFIG_SRC) || (echo "Missing $(KUBECONFIG_SRC). Run 'make ansible-k3s' first." && exit 1)
	@sed -i 's/127\.0\.0\.1/$(K3S_HOST_IP)/g' $(KUBECONFIG_SRC)
	@mkdir -p ~/.kube
	@cp $(KUBECONFIG_SRC) ~/.kube/config
	@chmod 600 ~/.kube/config
	@echo "Kubeconfig installed to ~/.kube/config (server https://$(K3S_HOST_IP):6443)"
	@$(KUBECTL) get nodes || (echo "kubectl get nodes failed - check K3s is Ready on $(K3S_HOST_IP)" && exit 1)

# helmfile implements `apply` as diff-then-sync, so helm-diff is required for
# `make apps`, not just `make apps-diff`. Helm 4 refuses plugins installed from a
# git URL and tarballs with no key to verify against, hence --keyring.
helm-diff: ## Install the helm-diff plugin and verify it against the K3s cluster
	@$(HELM) plugin list | grep -q '^diff' || $(HELM) plugin install --keyring $(HELM_DIFF_KEYRING) https://github.com/databus23/helm-diff/releases/latest/download/helm-diff-linux-amd64.tgz
	@$(HELMFILE) --file apps/k3s/helmfile.yaml list || (echo "helmfile list failed - run 'make kubectl-config' and confirm 'kubectl get nodes' is Ready" && exit 1)
	@echo "helm-diff ready. Try: make apps-diff"

# ── K3s apps (helmfile) ───────────────────────
#
# Everything below acts on apps/k3s/helmfile.yaml. To scope a run to one release,
# call helmfile directly:
#   mise exec -- helmfile --file apps/k3s/helmfile.yaml diff  -l name=headlamp
#   mise exec -- helmfile --file apps/k3s/helmfile.yaml apply -l name=headlamp

apps-diff: ## Show what would change for every release in apps/k3s/helmfile.yaml
	@$(HELMFILE) --file apps/k3s/helmfile.yaml diff

apps: ## Install/upgrade every release in apps/k3s/helmfile.yaml (idempotent)
	@$(HELMFILE) --file apps/k3s/helmfile.yaml apply
	@echo ""
	@echo "Headlamp:   https://dashboard.k3s.internal (token: make headlamp-token)"
	@echo "Grafana:    https://grafana.k3s.internal    (user: admin, password: make monitoring-password)"
	@echo "Prometheus: https://grafana-prometheus.k3s.internal"

apps-list: ## List the releases declared in apps/k3s/helmfile.yaml
	@$(HELMFILE) --file apps/k3s/helmfile.yaml list

apps-destroy: ## Uninstall every release in apps/k3s/helmfile.yaml (leaves monitoring PVCs behind)
	@$(HELMFILE) --file apps/k3s/helmfile.yaml destroy
	@echo "note: the monitoring PVCs come from StatefulSet volumeClaimTemplates, so they survive uninstall."
	@echo "      Reclaim them with: kubectl delete pvc -n monitoring --all"

headlamp-token: ## Print a Headlamp login token (ServiceAccount headlamp-admin)
	@$(KUBECTL) create token headlamp-admin -n headlamp --duration=24h

monitoring-password: ## Print the generated Grafana admin password
	@$(KUBECTL) get secret monitoring-grafana -n monitoring \
		-o jsonpath='{.data.admin-password}' | base64 -d; echo

clean: ## Remove venv
	@rm -rf $(ANSIBLE_DIR)/.venv
