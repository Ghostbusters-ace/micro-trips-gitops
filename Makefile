# Makefile pour orchestrer l'environnement Local-First (Micro-Trips)

export PATH := /home/linuxbrew/.linuxbrew/bin:/opt/homebrew/bin:$(PATH)

.PHONY: help deps cluster day0-terraform secrets day1-argocd all

help:
	@echo "🚀 Commandes de démarrage Micro-Trips :"
	@echo "  make deps           - 🛠️  Installe kubectl, kind, terraform et kubeseal (Mac/Linux/Codespace)"
	@echo "  make cluster        - 📦 Crée le cluster Kubernetes local avec Kind"
	@echo "  make day0-terraform - 🏗️  Lance Terraform (Installe ArgoCD et Sealed Secrets)"
	@echo "  make secrets        - 🔐 Injecte les mots de passe dans Vault & chiffre les Sealed Secrets"
	@echo "  make day1-argocd    - 🔄 Déploie l'application racine ArgoCD (App-of-Apps)"
	@echo "  make all            - ✨ Lance le cluster, Terraform, et ArgoCD d'un coup"

deps:
	@bash scripts/install-deps.sh

cluster:
	@echo "📦 Vérification du cluster Kind..."
	@if kind get clusters | grep -q "^micro-trips$$"; then \
		echo "✅ Le cluster 'micro-trips' existe déjà. On passe à la suite !"; \
	else \
		echo "🚀 Création du cluster Kind..."; \
		kind create cluster --name micro-trips; \
	fi
	kubectl cluster-info

day0-terraform:
	@echo "🏗️  Vérification et Amorçage de l'infrastructure (Day-0)..."
	cd terraform && terraform init
	@echo "🔍 1/3 - Validation syntaxique en cours..."
	cd terraform && terraform validate
	@echo "📝 2/3 - Simulation du déploiement (Dry-Run)..."
	cd terraform && terraform plan -out=tfplan
	@echo "🚀 3/3 - Tout est au vert ! Application des changements..."
	cd terraform && terraform apply "tfplan"
	@echo "✅ Terraform appliqué avec succès."

secrets:
	@echo "🔐 Injection des secrets dans Vault (Mode Prod)..."
	@# 1. Récupère le token root généré par le Job ArgoCD
	$(eval VAULT_TOKEN := $(shell kubectl get secret vault-prod-keys -n vault -o jsonpath='{.data.keys\.json}' | base64 -d | grep -o '"root_token":"[^"]*"' | cut -d'"' -f4))
	
	@# 2. Verifie que le moteur de secrets KV v2 est activé sur le chemin "secret/" (requis en mode prod)
	@kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN="$(VAULT_TOKEN)" vault secrets enable -path=secret kv-v2 > /dev/null 2>&1 || true
	
	@# 3. Charege les variables du .env.local et on les pousse dans Vault
	@set -a; source .env.local; set +a; \
	kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN="$(VAULT_TOKEN)" vault kv put secret/rabbitmq rabbitmq="$$RABBITMQ_PASSWORD"; \
	kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN="$(VAULT_TOKEN)" vault kv put secret/postgres password="$$POSTGRES_PASSWORD"
	@echo "✅ Les secrets ont été injectés avec succès dans le coffre Vault !"

day1-argocd:
	@echo "🔄 Lancement de la boucle GitOps (Day-1)..."
	kubectl apply -f bootstrap/
	@echo "✅ ArgoCD est en charge ! Regardez le cluster se déployer."

all: cluster day0-terraform day1-argocd secrets