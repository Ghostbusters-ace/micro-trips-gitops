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
  version    = "2.14.2"
  namespace  = "kube-system" #
}