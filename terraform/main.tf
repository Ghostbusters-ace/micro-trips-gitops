# 1. Création du namespace pour ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# 2. Installation d'ArgoCD via Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_version

  # On expose le serveur ArgoCD en NodePort pour y accéder en local
  set {
    name  = "server.service.type"
    value = "NodePort"
  }

  # Désactivation de la HA pour économiser la RAM en local
  set {
    name  = "redis.ha.enabled"
    value = "false"
  }

values = [
    yamlencode({
      configs = {
        # Config globale

        # Pour utiliser kustomize
        cm = {
          "kustomize.buildOptions" = "--enable-helm"
        }
        
        # Cette section génère automatiquement la ConfigMap 'argocd-cmd-params-cm'
        # Pour codespace
        params = {
          "server.insecure" = "true"
        }
      }
    })
  ]
}

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = var.sealed_secrets_version
  namespace  = "kube-system"
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_version
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

locals {
  env_file = file("${path.module}/../.env.local")
  
  vault_token_match = regexall("VAULT_TOKEN=([^\r\n]+)", local.env_file)
  
  # Si on le trouve on le prend, sinon met un token par defaut
  vault_token = length(local.vault_token_match) > 0 ? local.vault_token_match[0][0] : "root"
}

resource "kubernetes_secret" "vault_token" {
  metadata {
    name      = "vault-token"
    namespace = "external-secrets"
  }

  data = {
    token = local.vault_token 
  }

  type = "Opaque"
  depends_on = [helm_release.external_secrets]
}