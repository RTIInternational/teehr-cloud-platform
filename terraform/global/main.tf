# Account-wide resources shared by every regional stack in ../: CI and admin
# IAM, the Route 53 zone, and the CloudFront maintenance page. Kept apart so a
# regional stack can be built or destroyed without touching DNS or CI.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "TEEHR"
      Environment = var.environment
    }
  }
}

# CloudFront only accepts ACM certificates issued in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "TEEHR"
      Environment = var.environment
    }
  }
}

data "aws_caller_identity" "current" {}
