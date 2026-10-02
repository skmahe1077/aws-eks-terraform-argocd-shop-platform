provider "aws" {
  region = var.aws_region
}

# Reads connection details for a cluster that already exists - this root
# never creates the cluster, only installs Argo CD onto it. Run this only
# AFTER terraform/infrastructure has been applied.
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    # Uses your local AWS CLI credentials to mint a short-lived Kubernetes
    # auth token - the same approach `aws eks update-kubeconfig` sets up,
    # so no Kubernetes credentials are stored anywhere by Terraform.
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}
