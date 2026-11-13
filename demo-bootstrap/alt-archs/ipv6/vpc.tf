################################################################################
# VPC
################################################################################
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

variable "cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  azs  = local.azs

  # Uncomment if IPv6 or Dual-stack
  enable_ipv6                                    = true
  private_subnet_assign_ipv6_address_on_creation = true
  public_subnet_ipv6_prefixes                    = [0, 1, 2]
  private_subnet_ipv6_prefixes                   = [3, 4, 5]

  # Uncomment if IPv6 only
  # private_subnet_ipv6_native = true
  # public_subnet_ipv6_native  = true
  # enable_nat_gateway         = false
  # create_egress_only_igw     = true

  # Uncomment if IPv4 or Dual-stack
  cidr               = var.cidr_block
  private_subnets    = [for k, v in local.azs : cidrsubnet(var.cidr_block, 8, k)]
  public_subnets     = [for k, v in local.azs : cidrsubnet(var.cidr_block, 8, k + 4)]
  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
    "kubernetes.io/role/cni" = "1"
  }

  tags = local.tags
}
