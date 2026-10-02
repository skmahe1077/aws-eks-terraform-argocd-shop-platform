data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two AZs is enough for a workshop VPC and keeps NAT/EIP costs down.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# ---------------------------------------------------------------------------
# VPC - built with the official terraform-aws-modules/vpc module.
# This one module creates: the VPC itself, 2 public + 2 private subnets
# (one of each per AZ), an internet gateway, route tables, and (because
# single_nat_gateway = true) ONE NAT gateway shared by both private subnets
# - the cheapest option for a short-lived workshop cluster.
# ---------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  enable_nat_gateway = true
  single_nat_gateway = true # one NAT gateway for the whole workshop VPC, not one per AZ

  # Lets EKS and in-cluster load balancer controllers auto-discover
  # these subnets by role.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = {
    Project = var.name_prefix
  }
}

# ---------------------------------------------------------------------------
# EKS cluster - built with the official terraform-aws-modules/eks module.
# This module creates: the EKS control plane, its IAM role, a small managed
# node group (with its own IAM role and instance profile), the core EKS
# add-ons, and access-entry wiring so the operator and Terraform's own
# identity can use kubectl against the cluster.
# ---------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Public endpoint restricted to the supplied admin CIDR, plus private
  # access so nodes inside the VPC always reach the API server.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [var.admin_cidr]
  endpoint_private_access      = true

  # Adds the identity running `terraform apply` as a cluster admin via an
  # access entry - without this you can create the cluster but then have
  # no way to kubectl into it yourself.
  enable_cluster_creator_admin_permissions = true

  # Grants the workshop operator (a separate IAM principal, e.g. a
  # teammate or a shared workshop user) cluster-admin access too.
  access_entries = {
    operator = {
      principal_arn = var.operator_principal_arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  eks_managed_node_groups = {
    workshop = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }
  }

  tags = {
    Project = var.name_prefix
  }
}

# ---------------------------------------------------------------------------
# ECR repository for the application image.
# force_delete lets `terraform destroy` remove this repo even if it still
# has images in it - see the platform README's cleanup section for the
# manual alternative (aws ecr batch-delete-image) if you'd rather empty it
# by hand first.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "shop" {
  name                 = var.name_prefix
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.name_prefix
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC authentication.
# AWS allows only one OIDC provider per issuer URL per account, so if one
# for token.actions.githubusercontent.com already exists, reuse its ARN
# instead of creating a duplicate (pass it via
# existing_github_oidc_provider_arn).
# ---------------------------------------------------------------------------
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.existing_github_oidc_provider_arn == "" ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}

locals {
  github_oidc_provider_arn = var.existing_github_oidc_provider_arn != "" ? var.existing_github_oidc_provider_arn : aws_iam_openid_connect_provider.github_actions[0].arn
}

# IAM role GitHub Actions assumes via OIDC. The trust policy below is
# restricted to the APPLICATION repository and its deployment branch only
# (the platform repository never needs AWS access).
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository_owner}/${var.github_repository_name}:ref:refs/heads/${var.github_repository_branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.name_prefix}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Project = var.name_prefix
  }
}

# Scoped to exactly what the workflow needs: push images to this one ECR
# repository. No Kubernetes or EKS permissions are granted - Argo CD, not
# GitHub Actions, is responsible for deployment.
data "aws_iam_policy_document" "github_actions_ecr_push" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level permissions
  }

  statement {
    sid    = "PushToWorkshopRepository"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.shop.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_ecr_push" {
  name   = "${var.name_prefix}-ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_ecr_push.json
}
