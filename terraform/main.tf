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
          "features.structured-merge-diff" = "disable"
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

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "vault"
  create_namespace = true

set {
    name  = "server.dev.enabled"
    value = "false"
  }

set {
    name  = "server.ui.enabled"
    value = "true"
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = var.ingress_nginx_version

  set {
    name  = "controller.hostPort.enabled"
    value = "true"
  }
  set {
    name  = "controller.service.type"
    value = "NodePort"
  }
}