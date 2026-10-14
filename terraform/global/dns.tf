# teehr.rtiamanzi.org is delegated to this zone by NS records in the
# rtiamanzi.org zone in Azure DNS. See docs/maintenance-page.md.
resource "aws_route53_zone" "teehr" {
  name = var.dns_zone_name
}

# The Envoy load balancer belongs to a regional stack, so it comes in as
# variables; pointing them at another stack's ELB is the DNS cutover.
data "aws_elb_hosted_zone_id" "ingress" {
  region = var.ingress_elb_region
}

locals {
  envoy_target = {
    name    = var.ingress_elb_hostname
    zone_id = data.aws_elb_hosted_zone_id.ingress.id
  }

  maintenance_target = {
    name    = aws_cloudfront_distribution.maintenance.domain_name
    zone_id = aws_cloudfront_distribution.maintenance.hosted_zone_id
  }

  # Alias to the status record by name rather than to CloudFront, so the
  # wildcard has no dependency on the distribution (and its ACM validation)
  # and can be applied before the Azure delegation exists.
  status_target = {
    name    = "status.${var.dns_zone_name}"
    zone_id = aws_route53_zone.teehr.zone_id
  }

  ingress_target = var.maintenance_mode ? local.status_target : local.envoy_target
}

# Every app host (hub, api, dashboards, ...) resolves through this wildcard,
# matching the *.teehr CNAME it replaces in Azure.
resource "aws_route53_record" "wildcard" {
  zone_id = aws_route53_zone.teehr.zone_id
  name    = "*.${var.dns_zone_name}"
  type    = "A"

  alias {
    name                   = local.ingress_target.name
    zone_id                = local.ingress_target.zone_id
    evaluate_target_health = false
  }
}

# Always served from CloudFront so status.json stays reachable while the
# cluster is down.
resource "aws_route53_record" "status" {
  zone_id = aws_route53_zone.teehr.zone_id
  name    = "status.${var.dns_zone_name}"
  type    = "A"

  alias {
    name                   = local.maintenance_target.name
    zone_id                = local.maintenance_target.zone_id
    evaluate_target_health = false
  }
}
