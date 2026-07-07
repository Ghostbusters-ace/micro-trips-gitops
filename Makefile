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
	@echo "⏳ Attente de l'initialisation de Vault par le Job ArgoCD..."
	@kubectl wait --for=condition=complete job/vault-auto-init -n vault --timeout=120s > /dev/null 2>&1 || true
	@echo "🔐 Lancement du script d'injection (Isolation Bash)..."
	@bash -c '\
		echo "🔍 Récupération du Token Root..."; \
		B64=$$(kubectl get secret vault-prod-keys -n vault --template="{{ index .data \"keys.json\" }}"); \
		if [ -z "$$B64" ]; then echo "❌ Erreur: Le secret vault-prod-keys est introuvable ou vide."; exit 1; fi; \
		JSON=$$(echo "$$B64" | base64 -d); \
		TOKEN=$$(echo "$$JSON" | grep -Eo "\"root_token\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | cut -d"\"" -f4 | tr -d "\r\n "); \
		if [ -z "$$TOKEN" ]; then \
			echo "❌ Erreur: Impossible d extraire le root_token du JSON."; \
			echo "Voici le JSON récupéré pour comprendre le problème :"; \
			echo "$$JSON"; \
			exit 1; \
		fi; \
		echo "🔑 Token extrait avec succès. Activation du moteur KV v2..."; \
		kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$$TOKEN" vault secrets enable -path=secret kv-v2 > /dev/null 2>&1 || true; \
		echo "🔄 Lecture de .env.local..."; \
		DB_USER=$$(grep "^POSTGRES_USER=" .env.local | cut -d "=" -f2 | tr -d "\r\n"); \
		DB_PASS=$$(grep "^POSTGRES_PASSWORD=" .env.local | cut -d "=" -f2 | tr -d "\r\n"); \
		MQ_USER=$$(grep "^RABBITMQ_USER=" .env.local | cut -d "=" -f2 | tr -d "\r\n"); \
		MQ_PASS=$$(grep "^RABBITMQ_PASSWORD=" .env.local | cut -d "=" -f2 | tr -d "\r\n"); \
		echo "💾 Injection dans Vault : Postgres..."; \
		kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$$TOKEN" vault kv put secret/postgres POSTGRES_USER="$$DB_USER" POSTGRES_PASSWORD="$$DB_PASS"; \
		echo "💾 Injection dans Vault : RabbitMQ..."; \
		kubectl exec -n vault vault-0 -- env VAULT_TOKEN="$$TOKEN" vault kv put secret/rabbitmq RABBITMQ_DEFAULT_USER="$$MQ_USER" RABBITMQ_DEFAULT_PASS="$$MQ_PASS"; \
		echo "⚡ Notification à External Secrets Operator..."; \
		kubectl annotate externalsecret booking-db-secret -n micro-trips external-secrets.io/refresh="$$(date +%s)" --overwrite > /dev/null 2>&1 || true; \
		kubectl annotate externalsecret postgres-secret -n storage-messaging external-secrets.io/refresh="$$(date +%s)" --overwrite > /dev/null 2>&1 || true; \
		kubectl annotate externalsecret rabbitmq-secret -n storage-messaging external-secrets.io/refresh="$$(date +%s)" --overwrite > /dev/null 2>&1 || true; \
		echo "✅ Terminé avec succès !"; \
	'

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