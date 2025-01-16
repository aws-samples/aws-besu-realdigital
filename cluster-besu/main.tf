provider "aws" {
  region = local.region

  # Add standard retry configuration
  retry_mode  = "standard"
  max_retries = 3

  # Add default tags for all resources
  default_tags {
    tags = local.tags
  }

  # # Add assume role if needed for cross-account access
  # assume_role {
  #   role_arn = var.assume_role_arn
  # }
}

# Secondary provider for ECR Public access in us-east-1
provider "aws" {
  region = "us-east-1"
  alias  = "virginia"

  retry_mode  = "standard"
  max_retries = 3

  # Inherit the same tags
  default_tags {
    tags = local.tags
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}
