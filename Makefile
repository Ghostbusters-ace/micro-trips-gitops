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
	@echo "📦 Création du cluster Kind..."
	kind create cluster --name micro-trips
	kubectl cluster-info --context kind-micro-trips

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
	@echo "🔐 Configuration des Secrets Locaux..."
	@if [ ! -f .env.local ]; then echo "❌ Erreur : Fichier .env.local manquant. Copiez .env.example vers .env.local."; exit 1; fi
	@echo "✅ (Simulation) Secrets configurés à partir de .env.local"

day1-argocd:
	@echo "🔄 Lancement de la boucle GitOps (Day-1)..."
	kubectl apply -k bootstrap/
	@echo "✅ ArgoCD est en charge ! Regardez le cluster se déployer."

all: cluster day0-terraform secrets day1-argocd