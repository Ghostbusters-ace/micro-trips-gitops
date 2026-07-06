variable "kubeconfig_path" {
  description = "Chemin vers le fichier de configuration Kubernetes local (généré par kind)"
  type        = string
  default     = "~/.kube/config"
}

variable "argocd_version" {
  description = "Version spécifique du Chart Helm d'ArgoCD à installer"
  type        = string
  default     = "6.7.11"  # Version stable
}

variable "sealed_secrets_version" {
  description = "Version spécifique du Chart Helm de Bitnami Sealed Secrets"
  type        = string
  default     = "2.14.2"  # Version stable
}