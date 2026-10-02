provider "aws" {
  region = var.aws_region
}

# Used only for the GitHub Actions OIDC provider's TLS thumbprint - see
# the tls_certificate data source in main.tf.
provider "tls" {}
