.DEFAULT_GOAL := help

# Colors
BLUE := \033[36m
GREEN := \033[32m
RESET := \033[0m


.PHONY: help ping run-all check-ansible

##@ Help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Ansible Commands
ping: check-ansible ## Ping all servers
	ansible all -m ping  -K

run-all: check-ansible ## Run all playbooks
	ansible-playbook playbooks/*.yml -K

deploy-song-viewer: check-ansible ## Deploy song viewer	
	ansible-playbook playbooks/song-viewer.yml -K

##@ Utilities
check-ansible: ## Check if ansible is installed
	@which ansible > /dev/null || (echo "$(RED)Error: ansible is required but not installed.$(RESET)" && exit 1)

