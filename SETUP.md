
# 🚀 Guide de Démarrage (Codespace / Local)

Ce dépôt utilise une architecture **Local-First** pilotée par Terraform (Day-0) et ArgoCD (Day-1). 
Suivez ces étapes pour répliquer l'environnement en moins de 10 minutes.

## 📋 Prérequis
* Docker & `kind` installés
* `kubectl` et `terraform` installés
* L'utilitaire `kubeseal` installé (pour les secrets)

## 🏁 Démarrage Rapide

### Étape 1 : Gérer le Paradoxe des Secrets
Par sécurité, aucun secret n'est sur Git. Vous devez fournir vos identifiants locaux.
1. Dupliquez le fichier d'exemple : `cp .env.example .env.local`
2. Ouvrez `.env.local` et remplissez vos mots de passe (ex: Token Docker, Passwords DB).

### Étape 2 : Lancer l'Orchestrateur
À la racine du projet, lancez simplement la commande globale :
```bash
make all
```

**Que fait cette commande ?**

1. **`make cluster` :** Crée un cluster vierge via Kind.
2. **`make day0-terraform` :** Terraform provisionne les namespaces systèmes et installe les fondations (ArgoCD Core, Sealed Secrets Controller).
3. **`make secrets` :** Chiffre vos variables du fichier `.env.local` avec la nouvelle clé du cluster et peuple Vault.
4. **`make day1-argocd` :** Déploie le `root-app.yaml`. ArgoCD prend le relais et synchronise tout le reste (Bases de données, APIs, Linkerd, Grafana).
