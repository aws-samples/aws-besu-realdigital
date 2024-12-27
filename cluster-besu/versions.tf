terraform {
  required_version = ">= 1.5.0, < 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.9.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.18"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.1.0"
    }
  }
  backend "s3" {
    bucket = "xxxxxxxxxxxxx"
    key    = "cluster-besu/tfstate/cluster-besu.tfstate"
    region = "us-east-1"
  }
}
