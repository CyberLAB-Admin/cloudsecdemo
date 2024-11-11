# Makefile for Cloud Security Demo

# Variables
PROJECT_NAME ?= cloudsecdemo
ENVIRONMENT ?= secure
AWS_REGION ?= us-east-1
SHELL := /bin/bash

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[1;33m
NC := \033[0m

# Default target
.DEFAULT_GOAL := help

# Help target
help:
	@echo -e "${BLUE}Cloud Security Demo Management${NC}"
	@echo -e "${BLUE}=============================${NC}"
	@echo -e "\nUsage: make [target]\n"
	@echo -e "Targets:"
	@echo -e "  ${GREEN}setup${NC}          - Initial project setup"
	@echo -e "  ${GREEN}deploy${NC}         - Deploy infrastructure"
	@echo -e "  ${GREEN}destroy${NC}        - Destroy infrastructure"
	@echo -e "  ${GREEN}secure${NC}         - Switch to secure state"
	@echo -e "  ${GREEN}insecure${NC}       - Switch to insecure state"
	@echo -e "  ${GREEN}status${NC}         - Check infrastructure status"
	@echo -e "  ${GREEN}validate${NC}       - Validate configurations"
	@echo -e "  ${GREEN}monitor${NC}        - Deploy monitoring"
	@echo -e "  ${GREEN}test${NC}           - Run tests"
	@echo -e "  ${GREEN}clean${NC}          - Clean temporary files"

# Setup targets
.PHONY: setup
setup:
	@echo -e "${BLUE}Setting up project...${NC}"
	@./scripts/setup.sh

.PHONY: validate
validate:
	@echo -e "${BLUE}Validating configurations...${NC}"
	@./scripts/utils/validate_config.sh

# Deployment targets
.PHONY: deploy
deploy:
	@echo -e "${BLUE}Deploying infrastructure...${NC}"
	@./scripts/deploy.sh $(ENVIRONMENT)

.PHONY: destroy
destroy:
	@echo -e "${RED}Destroying infrastructure...${NC}"
	@./scripts/destroy.sh

# State management
.PHONY: secure
secure:
	@echo -e "${BLUE}Switching to secure state...${NC}"
	@./scripts/toggle.sh quick secure

.PHONY: insecure
insecure:
	@echo -e "${YELLOW}Switching to insecure state...${NC}"
	@./scripts/toggle.sh quick insecure

# Status and monitoring
.PHONY: status
status:
	@echo -e "${BLUE}Checking status...${NC}"
	@./scripts/status.sh --verbose

.PHONY: monitor
monitor:
	@echo -e "${BLUE}Deploying monitoring...${NC}"
	@./scripts/utils/monitor_deploy.sh

# Testing
.PHONY: test
test:
	@echo -e "${BLUE}Running tests...${NC}"
	@./scripts/utils/test.sh

# Cleanup
.PHONY: clean
clean:
	@echo -e "${BLUE}Cleaning up...${NC}"
	@find . -name "*.tfstate" -type f -delete
	@find . -name "*.tfstate.backup" -type f -delete
	@find . -name ".terraform" -type d -exec rm -rf {} +
	@find . -name "*.log" -type f -delete
	@find . -name "*.bak" -type f -delete
	@find . -name "node_modules" -type d -exec rm -rf {} +
	@rm -rf dist build .cache

# Development helpers
.PHONY: dev-setup
dev-setup: setup
	@pre-commit install
	@npm install
	@pip install -r requirements.txt

.PHONY: lint
lint:
	@pre-commit run --all-files

.PHONY: format
format:
	@terraform fmt -recursive ./terraform
	@black .
	@prettier --write "**/*.{js,jsx,ts,tsx,json,md,yaml,yml}"

# Documentation
.PHONY: docs
docs:
	@echo -e "${BLUE}Generating documentation...${NC}"
	@./scripts/utils/generate_docs.sh

# Backup and restore
.PHONY: backup
backup:
	@echo -e "${BLUE}Creating backup...${NC}"
	@./scripts/utils/backup.sh --full

.PHONY: restore
restore:
	@echo -e "${BLUE}Restoring from backup...${NC}"
	@./scripts/utils/backup.sh --restore $(backup)

# CI/CD helpers
.PHONY: ci-setup
ci-setup:
	@./scripts/utils/ci_setup.sh

.PHONY: ci-deploy
ci-deploy:
	@./scripts/utils/ci_deploy.sh

.PHONY: ci-test
ci-test:
	@./scripts/utils/ci_test.sh

# Dependencies
deploy: validate
secure: validate
insecure: validate
monitor: validate
