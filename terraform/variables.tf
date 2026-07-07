variable "kubeconfig_path" {
  description = "Chemin vers le fichier de configuration Kubernetes local (généré par kind)"
  type        = string
  default     = "~/.kube/config"
}

variable "argocd_version" {
  description = "Version spécifique du Chart Helm d'ArgoCD à installer"
  type        = string
  default     = "10.1.2"
}

variable "sealed_secrets_version" {
  description = "Version spécifique du Chart Helm de Bitnami Sealed Secrets"
  type        = string
  default     = "2.14.2"  # Version stable
}

variable "external_secrets_version" {
  description = "Version spécifique du Chart Helm d'External Secrets Operator"
  type        = string
  default     = "2.7.0"
}

variable "ingress_nginx_version" {
  description = "Version spécifique du Chart Helm d'Ingress NGINX"
  type        = string
  default     = "4.15.1"
}