# Checked against the current Argo CD Helm chart (argoproj/argo-helm) as
# of writing this workshop - see README for the chart's release page.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }
}
