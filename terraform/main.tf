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
}

# 3. Installation du contrôleur Sealed Secrets (Pour décoder les secrets Git)
resource "kubernetes_namespace" "sealed_secrets" {
  metadata {
    name = "kube-system"
  }
}

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  namespace  = "kube-system"
  version    = var.sealed_secrets_version
}