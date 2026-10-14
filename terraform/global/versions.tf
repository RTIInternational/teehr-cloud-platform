terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      # ref: https://registry.terraform.io/providers/hashicorp/aws/latest
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "teehr-terraform-state"
    key          = "terraform/global/state"
    region       = "us-east-2"
    use_lockfile = true
  }
}
