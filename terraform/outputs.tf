output "nfs_server_dns" {
  value = aws_efs_file_system.datadir.dns_name
}

output "cluster_arn" {
  value = module.eks.cluster_arn
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_garden_deploy.arn
  description = "ARN of the GitHub Actions role for Garden deployments"
}

output "github_actions_role_name" {
  value       = aws_iam_role.github_actions_garden_deploy.name
  description = "Name of the GitHub Actions role for Garden deployments"
}

output "s3_vpc_endpoint_id" {
  value       = aws_vpc_endpoint.s3.id
  description = "ID of the S3 VPC Gateway Endpoint for cost-free S3 access"
}

output "iceberg_s3_warehouse_readonly_role_arn" {
  value       = aws_iam_role.iceberg_s3_warehouse_readonly_irsa.arn
  description = "ARN of the read-only IAM role for the Jupyter service account to access external, non-warehouse data (e.g. ciroh-rti-hefs-data)"
}

output "iceberg_s3_warehouse_rw_role_arn" {
  value       = aws_iam_role.iceberg_s3_warehouse_access.arn
  description = "ARN of the read-write IAM role for the Iceberg warehouse bucket, assumable only by Polaris (teehr-hub-polaris-irsa) to vend scoped credentials to catalog clients"
}

output "polaris_role_arn" {
  value       = aws_iam_role.polaris_irsa.arn
  description = "ARN of the IRSA role for the Polaris service account, used to assume the warehouse data-access role and vend S3 credentials"
}

output "prefect_job_role_arn" {
  value       = aws_iam_role.prefect_job_irsa.arn
  description = "ARN of the IRSA role for the prefect-job service account, for non-catalog S3 access (icechunk) alongside Polaris-vended catalog credentials"
}

output "xpublish_api_role_arn" {
  value       = aws_iam_role.xpublish_api_irsa.arn
  description = "ARN of the IRSA role for the xpublish-api service account, granting read-only access to the icechunk warehouse bucket"
}

output "icechunk_warehouse_bucket" {
  value       = aws_s3_bucket.teehr_icechunk_warehouse.bucket
  description = "Name of the icechunk warehouse bucket backing the gridded-data (xpublish-api) stack"
}
