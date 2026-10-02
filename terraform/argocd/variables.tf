variable "aws_region" {
  description = "AWS region the EKS cluster runs in. Must match terraform/infrastructure."
  type        = string
  default     = "eu-west-2"
}

variable "cluster_name" {
  description = "Name of the existing EKS cluster (terraform/infrastructure output: cluster_name)."
  type        = string
  default     = "workshop-shop-eks"
}

variable "argocd_namespace" {
  description = "Kubernetes namespace to install Argo CD into."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart (argoproj/argo-helm). Check https://github.com/argoproj/argo-helm/releases for the current version before changing this."
  type        = string
  default     = "10.9.6"
}
