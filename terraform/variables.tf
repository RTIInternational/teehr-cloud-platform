variable "region" {
  type        = string
  description = <<-EOT
  AWS region to perform all our operations in.
  EOT
}

variable "cluster_name" {
  type        = string
  description = <<-EOT
  Name of the EKS cluster.
  EOT
}

variable "cluster_version" {
  type        = string
  description = <<-EOT
  Version of the EKS cluster to create.
  EOT
}

variable "environment" {
  type        = string
  description = <<-EOT
  Deployment environment (e.g., dev, staging, prod).
  EOT
}

variable "project_name" {
  type        = string
  description = <<-EOT
  Name of the project.
  EOT
}

variable "project_ids" {
  type        = list(string)
  default     = []
  description = <<-EOT
  List of CIROH project IDs. For each project ID, dedicated node groups will be created
  (nb-r5-xlarge-{id}, nb-r5-4xlarge-{id}, spark-r5-4xlarge-spot-{id}) for tracking usage.
  EOT
}

variable "azs" {
  type        = list(string)
  default     = null
  description = <<-EOT
  Availability zones for the VPC; node groups and the EFS mount target use the
  first. Defaults to the region's first three. Pick zones that offer every node
  instance type (r5, r5a, r5n).
  EOT
}

variable "iceberg_warehouse_bucket" {
  type        = string
  description = <<-EOT
  Name of the Iceberg warehouse bucket.
  EOT
}

variable "icechunk_warehouse_bucket" {
  type        = string
  description = <<-EOT
  Name of the icechunk/PMTiles bucket backing xpublish-api.
  EOT
}

variable "admin_role_name" {
  type        = string
  default     = "teehr-hub-teehr-hub-admin"
  description = <<-EOT
  Admin role (managed in global/) granted cluster admin on this cluster.
  EOT
}

variable "terraform_plan_role_name" {
  type        = string
  default     = "teehr-hub-github-actions-terraform-plan"
  description = <<-EOT
  Terraform workflow plan role (managed in global/) granted read-only access
  on this cluster.
  EOT
}

variable "terraform_apply_role_name" {
  type        = string
  default     = "teehr-hub-github-actions-terraform-apply"
  description = <<-EOT
  Terraform workflow apply role (managed in global/) granted cluster admin on
  this cluster.
  EOT
}

variable "legacy_iam_names" {
  type        = bool
  default     = false
  description = <<-EOT
  Keep the original unprefixed IAM role names (ClusterAutoscalerIRSA,
  AmazonEKS_EBS_CSI_DriverRole, ...). Only the us-east-2 stack sets this; IAM
  names are account-wide, so any other stack needs the cluster-prefixed names.
  EOT
}

variable "cluster_creator_admin" {
  type        = bool
  default     = false
  description = <<-EOT
  Give the identity running Terraform a cluster-admin access entry. Needed on a
  new cluster for the kubernetes/helm providers; turn it off once it's built.
  EOT
}

variable "create_default_storage_class" {
  type        = bool
  default     = false
  description = <<-EOT
  Create a gp3 StorageClass and mark it the cluster default. Needed on clusters
  created on Kubernetes 1.30+, where EKS no longer marks gp2 as default.
  EOT
}

variable "efs_replication_overwrite" {
  type        = string
  default     = "ENABLED"
  description = <<-EOT
  EFS replication overwrite protection for /data. DISABLED allows another
  file system to replicate into this one.
  EOT
}

variable "efs_replication_destination" {
  type = object({
    file_system_id = string
    region         = string
  })
  default     = null
  description = <<-EOT
  Existing file system in another region to replicate /data into. Its stack
  must set efs_replication_overwrite = "DISABLED" first.
  EOT
}

variable "additional_ecr_repos" {
  type = list(object({
    name            = string
    max_image_count = number
  }))
  default     = []
  description = <<-EOT
  Extra ECR repositories for this stack only, e.g. images built outside the
  deployment repos (hefs-fews-hub).
  EOT
}

variable "enable_ipv6_egress" {
  type        = bool
  default     = false
  description = <<-EOT
  Give private subnets and nodes IPv6 and route it through an egress-only
  internet gateway, so traffic to IPv6 destinations skips the NAT gateway. Only teehr-hub-use1 sets this.
  EOT
}

variable "db_backup_bucket" {
  type        = string
  description = <<-EOT
  Name of the bucket for Postgres backups (teehr-cloud-core db-backups).
  EOT
}

variable "db_backup_retention_days" {
  type        = number
  default     = 35
  description = <<-EOT
  Days to keep each Postgres backup. Older dumps, and overwritten or deleted
  versions after 7 days, are expired.
  EOT
}

variable "upload_staging_bucket" {
  type        = string
  description = <<-EOT
  Name of the bucket where uploaded files wait to be inspected and loaded
  (teehr-cloud-core control-plane).
  EOT
}

variable "upload_staging_retention_days" {
  type        = number
  default     = 7
  description = <<-EOT
  Days a staged upload is kept. A load reads its file within minutes of the ingest;
  anything older is an abandoned upload.
  EOT
}

variable "upload_cors_origins" {
  type        = list(string)
  default     = []
  description = <<-EOT
  Web origins allowed to PUT files to the staging bucket from a browser (e.g.
  https://dashboards.<hostname>). Empty: no CORS rule.
  EOT
}
