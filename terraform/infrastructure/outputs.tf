output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "aws_region" {
  description = "AWS region the cluster and ECR repository were created in."
  value       = var.aws_region
}

output "ecr_repository_url" {
  description = "ECR repository URL - set as the ECR_REPOSITORY_URL variable in the application repository."
  value       = aws_ecr_repository.shop.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN GitHub Actions assumes via OIDC - set as the AWS_ROLE_ARN variable in the application repository."
  value       = aws_iam_role.github_actions.arn
}

output "configure_kubectl_command" {
  description = "Run this to configure kubectl for the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
