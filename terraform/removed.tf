# These moved to the global root (global/imports.tf adopts them). Forget them
# here without destroying anything. Safe to delete once applied, along with
# this provider, which Terraform needs to forget the ACM resources.

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

removed {
  from = aws_iam_group.teehr_hub_admins
  lifecycle { destroy = false }
}

removed {
  from = aws_iam_group_policy.teehr_hub_admins_assume_role
  lifecycle { destroy = false }
}

removed {
  from = aws_iam_role.teehr_hub_admin
  lifecycle { destroy = false }
}

removed {
  from = aws_iam_openid_connect_provider.github_actions
  lifecycle { destroy = false }
}

removed {
  from = aws_iam_role.github_actions_garden_deploy
  lifecycle { destroy = false }
}

removed {
  from = aws_iam_role_policy.github_actions_garden_deploy
  lifecycle { destroy = false }
}

removed {
  from = aws_route53_zone.teehr
  lifecycle { destroy = false }
}

removed {
  from = aws_route53_record.wildcard
  lifecycle { destroy = false }
}

removed {
  from = aws_route53_record.status
  lifecycle { destroy = false }
}

removed {
  from = aws_route53_record.maintenance_cert_validation
  lifecycle { destroy = false }
}

removed {
  from = aws_acm_certificate.maintenance
  lifecycle { destroy = false }
}

removed {
  from = aws_acm_certificate_validation.maintenance
  lifecycle { destroy = false }
}

removed {
  from = aws_cloudfront_distribution.maintenance
  lifecycle { destroy = false }
}

removed {
  from = aws_cloudfront_origin_access_control.maintenance
  lifecycle { destroy = false }
}

removed {
  from = aws_cloudfront_function.maintenance_request
  lifecycle { destroy = false }
}

removed {
  from = aws_cloudfront_function.maintenance_response
  lifecycle { destroy = false }
}

removed {
  from = aws_cloudfront_response_headers_policy.status_cors
  lifecycle { destroy = false }
}

removed {
  from = aws_s3_bucket.maintenance
  lifecycle { destroy = false }
}

removed {
  from = aws_s3_bucket_public_access_block.maintenance
  lifecycle { destroy = false }
}

removed {
  from = aws_s3_bucket_policy.maintenance
  lifecycle { destroy = false }
}

removed {
  from = aws_s3_object.maintenance_index
  lifecycle { destroy = false }
}

removed {
  from = aws_s3_object.maintenance_status
  lifecycle { destroy = false }
}
