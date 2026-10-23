output "teehr_zone_name_servers" {
  value       = aws_route53_zone.teehr.name_servers
  description = "Name servers to add as the teehr NS record in the rtiamanzi.org Azure DNS zone"
}

output "maintenance_cloudfront_domain" {
  value       = aws_cloudfront_distribution.maintenance.domain_name
  description = "CloudFront domain serving the maintenance page and status.json"
}

output "teehr_hub_admin_role_arn" {
  value       = aws_iam_role.teehr_hub_admin.arn
  description = "ARN of the admin role granted cluster admin on every regional cluster"
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_garden_deploy.arn
  description = "ARN of the GitHub Actions role for Garden deployments"
}

output "github_actions_role_name" {
  value       = aws_iam_role.github_actions_garden_deploy.name
  description = "Name of the GitHub Actions role for Garden deployments"
}

output "github_actions_terraform_plan_role_arn" {
  value       = aws_iam_role.github_actions_terraform_plan.arn
  description = "ARN of the role the Terraform workflow's plan job assumes"
}

output "github_actions_terraform_apply_role_arn" {
  value       = aws_iam_role.github_actions_terraform_apply.arn
  description = "ARN of the role the Terraform workflow's apply job assumes"
}
