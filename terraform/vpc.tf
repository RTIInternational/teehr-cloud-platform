module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.cluster_name}-vpc"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  # intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  # enable_dns_hostnames = true
  # enable_dns_support   = true
  enable_nat_gateway = true
  single_nat_gateway = true

  # IPv6 egress: private subnets get IPv6 and a ::/0 route to an egress-only
  # internet gateway. IPv4 traffic still uses the NAT gateway.
  enable_ipv6                                    = var.enable_ipv6_egress
  private_subnet_ipv6_prefixes                   = var.enable_ipv6_egress ? [for k, v in local.azs : k] : []
  private_subnet_assign_ipv6_address_on_creation = var.enable_ipv6_egress
  # DNS64 would give IPv4-only hosts, S3 included, IPv6 addresses routed through
  # the NAT gateway, which would take S3 traffic off the gateway endpoint.
  private_subnet_enable_dns64                                   = false
  private_subnet_enable_resource_name_dns_aaaa_record_on_launch = false

  tags = local.tags

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# S3 VPC Gateway Endpoint
# This endpoint allows S3 traffic to stay within the AWS network,
# avoiding data transfer charges when accessing S3 buckets like
# s3://noaa-nwm-retrospective-3-0-pds/ from within the VPC
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"

  route_table_ids = module.vpc.private_route_table_ids

  tags = merge(
    local.tags,
    {
      Name = "${local.cluster_name}-s3-endpoint"
    }
  )
}

# module "vpc_cni_irsa" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   version = "~> 5.0"

#   role_name_prefix      = "VPC-CNI-IRSA"
#   attach_vpc_cni_policy = true
#   vpc_cni_enable_ipv4   = true

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:aws-node"]
#     }
#   }

#   tags = local.tags
# }
