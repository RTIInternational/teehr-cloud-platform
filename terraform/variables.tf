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

variable "cluster_nodes_location" {
  type        = string
  description = <<-EOT
  Location of the nodes of the kubernetes cluster.
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

variable "dns_zone_name" {
  type        = string
  default     = "teehr.rtiamanzi.org"
  description = <<-EOT
  Route 53 hosted zone delegated from the rtiamanzi.org zone in Azure DNS.
  EOT
}

variable "maintenance_mode" {
  type        = bool
  default     = false
  description = <<-EOT
  When true, *.<dns_zone_name> points at the CloudFront maintenance page instead
  of the Envoy load balancer.
  EOT
}

variable "maintenance_message" {
  type        = string
  default     = ""
  description = <<-EOT
  Message published in status.json, shown on the maintenance page and as a
  banner in the apps. Set it ahead of planned maintenance; empty means no banner.
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
