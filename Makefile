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
	cd terraform && terraform validate
	cd terraform && terraform plan -out=tfplan
	cd terraform && terraform apply "tfplan"
	@echo "✅ Terraform appliqué avec succès."
	
	@echo "🧹 Nettoyage d'un ancien Job Vault si existant..."
	kubectl delete job vault-auto-init -n vault --ignore-not-found
	
	@echo "🚀 Lancement du Job d'initialisation de Vault..."
	kubectl apply -f scripts/k8s/vault-init-job.yaml

secrets:
	@echo "⏳ Attente de l'initialisation de Vault par le Job..."
	@kubectl wait --for=condition=complete job/vault-auto-init -n vault --timeout=300s || (echo "❌ Le Job d'initialisation a échoué" && exit 1)
	
	@echo "🔐 Injection des secrets dans Vault (Mode Prod)..."

	@VAULT_TOKEN=$$(kubectl get secret vault-prod-keys -n vault -o jsonpath='{.data.keys\.json}' | base64 -d | jq -r '.root_token'); \
	if [ -z "$$VAULT_TOKEN" ] || [ "$$VAULT_TOKEN" = "null" ]; then echo "❌ Erreur: Impossible de récupérer le token valide"; exit 1; fi; \
	echo "✅ Token récupéré avec succès !"; \
	kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN="$$VAULT_TOKEN" vault secrets enable -path=secret kv-v2 > /dev/null 2>&1 || true; \
	echo "🔄 Écriture des secrets dans Vault..."; \
	set -a; source .env.local; set +a; \
	kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN="$$VAULT_TOKEN" vault kv put secret/postgres POSTGRES_USER="$$POSTGRES_USER" POSTGRES_PASSWORD="$$POSTGRES_PASSWORD"; \
	kubectl exec -i -n vault vault-0 -- env VAULT_TOKEN="$$VAULT_TOKEN" vault kv put secret/rabbitmq RABBITMQ_DEFAULT_USER="$$RABBITMQ_USER" RABBITMQ_DEFAULT_PASS="$$RABBITMQ_PASSWORD"
	@echo "✅ Les secrets ont été injectés."

day1-argocd:
	@echo "🔄 Lancement de la boucle GitOps (Day-1)..."
	kubectl apply -f bootstrap/
	
	@echo "⚡ Notification à External Secrets Operator (Post-Sync)..."
	@sleep 10
	@kubectl annotate externalsecret booking-db-secret -n micro-trips external-secrets.io/refresh="$$(date +%s)" --overwrite > /dev/null 2>&1 || true
	@kubectl annotate externalsecret postgres-secret -n storage-messaging external-secrets.io/refresh="$$(date +%s)" --overwrite > /dev/null 2>&1 || true
	@kubectl annotate externalsecret rabbitmq-secret -n storage-messaging external-secrets.io/refresh="$$(date +%s)" --overwrite > /dev/null 2>&1 || true
	@echo "✅ ArgoCD est en charge ! Regardez le cluster se déployer."

all: cluster day0-terraform secrets day1-argocd