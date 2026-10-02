variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-2"
}

variable "name_prefix" {
  description = "Prefix used for naming AWS resources (ECR repo, IAM role, etc.)."
  type        = string
  default     = "workshop-shop"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "workshop-shop-eks"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Check https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html for currently supported versions before changing this."
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# --- GitHub OIDC trust (application repository only) ------------------

variable "github_repository_owner" {
  description = "GitHub username or organisation that owns the APPLICATION repository (shop-app) - NOT the platform repository."
  type        = string
}

variable "github_repository_name" {
  description = "Name of the APPLICATION repository (aws-eks-terraform-argocd-shop-app), used to restrict the GitHub Actions IAM role's trust policy."
  type        = string
  default     = "aws-eks-terraform-argocd-shop-app"
}

variable "github_repository_branch" {
  description = "Branch of the application repository allowed to assume the GitHub Actions IAM role."
  type        = string
  default     = "main"
}

variable "existing_github_oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC provider in this AWS account, if one already exists. Leave empty to have Terraform create one - AWS accounts only allow one OIDC provider per URL, so reuse an existing one instead of trying to create a duplicate."
  type        = string
  default     = ""
}

# --- Cluster access -----------------------------------------------------

variable "operator_principal_arn" {
  description = "IAM principal ARN (user or role) for the workshop operator who needs kubectl/EKS access, e.g. arn:aws:iam::123456789012:user/alex."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block (your IP, e.g. 203.0.113.4/32) allowed to reach the EKS public API endpoint."
  type        = string
}
