.PHONY: help setup clean all \
        tf-init tf-plan tf-apply tf-destroy \
        ansible-install ansible-all ansible-adguard ansible-docker ansible-plex ansible-k3s ansible-pve ansible-pve-host ansible-dry-run \
        vault-create terraform-tfvars docker-context ssh-accept-keys ssh-cleanup \
        kubectl-install kubectl-config kubectl-setup \
        helm-install helm-setup \
        helmfile-install helmfile-setup \
        apps apps-diff apps-list apps-destroy \
        headlamp-token monitoring-password

ANSIBLE_DIR := ansible
TERRAFORM_DIR := terraform
DOCKER_USER ?= skoltun
DOCKER_HOST_IP := 192.168.1.102
PROXMOX_HOST_IP := 192.168.1.100
K3S_HOST_IP := 192.168.1.104
KUBECONFIG_SRC := ansible/playbooks/files/k3s.yaml
HELM_VERSION ?=
HELM_INSTALLER := /tmp/get-helm-4
HELM_INSTALLER_URL := https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
export HELM_VERSION   # consumed by get-helm-4 via --version
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

# ── K3s / kubectl / helm / helmfile ────────────

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

helm-install: ## Install Helm CLI (official get-helm-4 script; prompts for sudo)
	@curl -fsSL -o $(HELM_INSTALLER) $(HELM_INSTALLER_URL)
	@chmod 700 $(HELM_INSTALLER)
	@$(HELM_INSTALLER) $(if $(HELM_VERSION),--version $(HELM_VERSION))

helm-setup: helm-install ## Install Helm and verify it against the K3s cluster (opt-in)
	@helm list -A || (echo "helm list -A failed - run 'make kubectl-setup' and confirm 'kubectl get nodes' is Ready" && exit 1)
	@echo "helm ready. Try: helm repo add jetstack https://charts.jetstack.io && helm search repo jetstack"

# ── Helmfile ───────────────────────────────────

helmfile-install: ## Install helmfile CLI (SHA256-verified release tarball; prompts for sudo)
	@cd /tmp && curl -fsSLO https://github.com/helmfile/helmfile/releases/download/v1.8.0/helmfile_1.8.0_linux_amd64.tar.gz
	@cd /tmp && curl -fsSLO https://github.com/helmfile/helmfile/releases/download/v1.8.0/helmfile_1.8.0_checksums.txt
	@cd /tmp && sha256sum --ignore-missing -c helmfile_1.8.0_checksums.txt
	@cd /tmp && tar xzf helmfile_1.8.0_linux_amd64.tar.gz helmfile && sudo mv helmfile /usr/local/bin/helmfile
	@helmfile --version

helmfile-setup: helmfile-install ## Install helmfile + the helm-diff plugin and verify against the K3s cluster (opt-in)
	@helm plugin list | grep -q '^diff' || helm plugin install --keyring keys/helm-diff.gpg https://github.com/databus23/helm-diff/releases/latest/download/helm-diff-linux-amd64.tgz
	@helmfile --file apps/k3s/helmfile.yaml list || (echo "helmfile list failed - run 'make kubectl-setup' and confirm 'kubectl get nodes' is Ready" && exit 1)
	@echo "helmfile ready. Try: make apps-diff"

# ── K3s apps (helmfile) ───────────────────────
#
# Everything below acts on apps/k3s/helmfile.yaml. To scope a run to one release,
# call helmfile directly:
#   helmfile --file apps/k3s/helmfile.yaml diff  -l name=headlamp
#   helmfile --file apps/k3s/helmfile.yaml apply -l name=headlamp

apps-diff: ## Show what would change for every release in apps/k3s/helmfile.yaml
	@helmfile --file apps/k3s/helmfile.yaml diff

apps: ## Install/upgrade every release in apps/k3s/helmfile.yaml (idempotent)
	@helmfile --file apps/k3s/helmfile.yaml apply
	@echo ""
	@echo "Headlamp:   https://dashboard.k3s.internal (token: make headlamp-token)"
	@echo "Grafana:    https://grafana.k3s.internal    (user: admin, password: make monitoring-password)"
	@echo "Prometheus: https://grafana-prometheus.k3s.internal"

apps-list: ## List the releases declared in apps/k3s/helmfile.yaml
	@helmfile --file apps/k3s/helmfile.yaml list

apps-destroy: ## Uninstall every release in apps/k3s/helmfile.yaml (leaves monitoring PVCs behind)
	@helmfile --file apps/k3s/helmfile.yaml destroy
	@echo "note: the monitoring PVCs come from StatefulSet volumeClaimTemplates, so they survive uninstall."
	@echo "      Reclaim them with: kubectl delete pvc -n monitoring --all"

headlamp-token: ## Print a Headlamp login token (ServiceAccount headlamp-admin)
	@kubectl create token headlamp-admin -n headlamp --duration=24h

monitoring-password: ## Print the generated Grafana admin password
	@kubectl get secret monitoring-grafana -n monitoring \
		-o jsonpath='{.data.admin-password}' | base64 -d; echo

clean: ## Remove venv
	@rm -rf $(ANSIBLE_DIR)/.venv
