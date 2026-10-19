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
  new cluster for the kubernetes/helm providers.
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
