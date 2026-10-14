terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      # ref: https://registry.terraform.io/providers/hashicorp/aws/latest
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13"
    }
  }

  # One state per regional stack: terraform init -backend-config=backends/<stack>.hcl
  backend "s3" {}
}
