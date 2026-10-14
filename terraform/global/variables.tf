variable "region" {
  type        = string
  description = <<-EOT
  Default region for regional resources here (the maintenance page bucket).
  EOT
}

variable "name" {
  type        = string
  description = <<-EOT
  Prefix for the shared IAM roles (e.g. <name>-teehr-hub-admin).
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

variable "ingress_elb_hostname" {
  type        = string
  description = <<-EOT
  Hostname of the Envoy load balancer that *.<dns_zone_name> points at. Take it
  from the active regional stack's `ingress_elb_hostname` output.
  EOT
}

variable "ingress_elb_region" {
  type        = string
  description = <<-EOT
  Region of the load balancer in ingress_elb_hostname.
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
