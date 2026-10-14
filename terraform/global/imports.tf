# Adopts resources that the us-east-2 stack in ../ created before this root
# existed (see the matching removed blocks in ../removed.tf). Safe to delete
# once applied. aws_acm_certificate_validation isn't importable; it's
# recreated, which only waits on the already-issued certificate.

import {
  to = aws_iam_group.teehr_hub_admins
  id = "TeehrHubAdmins"
}

import {
  to = aws_iam_group_policy.teehr_hub_admins_assume_role
  id = "TeehrHubAdmins:TeehrHubAdminsAssumeRole"
}

import {
  to = aws_iam_role.teehr_hub_admin
  id = "teehr-hub-teehr-hub-admin"
}

import {
  to = aws_iam_openid_connect_provider.github_actions
  id = "arn:aws:iam::935462133478:oidc-provider/token.actions.githubusercontent.com"
}

import {
  to = aws_iam_role.github_actions_garden_deploy
  id = "teehr-hub-github-actions-garden-deploy"
}

import {
  to = aws_iam_role_policy.github_actions_garden_deploy
  id = "teehr-hub-github-actions-garden-deploy:github-actions-garden-deploy-policy"
}

import {
  to = aws_route53_zone.teehr
  id = "Z0887337199ZRE6F5NLS2"
}

import {
  to = aws_route53_record.wildcard
  id = "Z0887337199ZRE6F5NLS2_*.teehr.rtiamanzi.org_A"
}

import {
  to = aws_route53_record.status
  id = "Z0887337199ZRE6F5NLS2_status.teehr.rtiamanzi.org_A"
}

import {
  to = aws_route53_record.maintenance_cert_validation["*.teehr.rtiamanzi.org"]
  id = "Z0887337199ZRE6F5NLS2__3d2237058b25563d83d2dc4eddda2f2e.teehr.rtiamanzi.org._CNAME"
}

import {
  to = aws_acm_certificate.maintenance
  id = "arn:aws:acm:us-east-1:935462133478:certificate/660ff7a8-374d-4b7d-bf36-de9e6918d64b"
}

import {
  to = aws_cloudfront_distribution.maintenance
  id = "E2X9BMS4HP5VUT"
}

import {
  to = aws_cloudfront_origin_access_control.maintenance
  id = "EUW2USIL8YGFF"
}

import {
  to = aws_cloudfront_function.maintenance_request
  id = "dev-teehr-maintenance-request"
}

import {
  to = aws_cloudfront_function.maintenance_response
  id = "dev-teehr-maintenance-response"
}

import {
  to = aws_cloudfront_response_headers_policy.status_cors
  id = "61614b2c-f8df-47f1-9850-c321a530e960"
}

import {
  to = aws_s3_bucket.maintenance
  id = "dev-teehr-maintenance-page"
}

import {
  to = aws_s3_bucket_public_access_block.maintenance
  id = "dev-teehr-maintenance-page"
}

import {
  to = aws_s3_bucket_policy.maintenance
  id = "dev-teehr-maintenance-page"
}

import {
  to = aws_s3_object.maintenance_index
  id = "dev-teehr-maintenance-page/index.html"
}

import {
  to = aws_s3_object.maintenance_status
  id = "dev-teehr-maintenance-page/status.json"
}
