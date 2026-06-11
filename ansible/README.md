# Ansible Configuration

This directory contains the automation playbooks for configuring your Proxmox-managed infrastructure.

## Prerequisites
* **Ansible Core:** 2.21.0 or higher
* **Python:** 3.12+
* **Environment:** WSL2 / Linux

## Getting Started

### 1. Install Dependencies
Before running the playbooks, ensure all required Ansible collections are installed from the root directory:
```bash
ansible-galaxy install -r requirements.yml