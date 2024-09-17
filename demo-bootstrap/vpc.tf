################################################################################
# VPC
################################################################################
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 4)
}

variable "cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The CIDR block for the VPC"
}

variable "secondary_cidr_block" {
  type        = string
  default     = "100.0.0.0/16"
  description = "The CIDR block for the VPC"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = var.cidr_block
  #secondary_cidr_blocks = [var.secondary_cidr_block] # can add up to 5 total CIDR blocks

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.cidr_block, 3, k)]
  #private_subnets = concat([for k, v in local.azs : cidrsubnet(var.cidr_block, 4, k)], [for k, v in local.azs : cidrsubnet(var.secondary_cidr_block, 2, k)])
  public_subnets = [for k, v in local.azs : cidrsubnet(var.cidr_block, 4, k + 8)]

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

# resource "kubernetes_manifest" "eni_config" {
#   for_each = zipmap(local.azs, slice(module.vpc.private_subnets, 3, 6))

#   manifest = {
#     apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
#     kind       = "ENIConfig"
#     metadata = {
#       name = each.key
#     }
#     spec = {
#       securityGroups = [
#         module.eks.node_security_group_id,
#       ]
#       subnet = each.value
#     }
#   }
# }

# resource "aws_ec2_tag" "karpenter_subnets" {
#   for_each = zipmap(local.azs, slice(module.vpc.private_subnets, 0, 3))

#   resource_id = each.value
#   key         = "karpenter.sh/discovery"
#   value       = local.name
# }

resource "aws_vpc_ipv4_cidr_block_association" "secondary_cidr" {
  vpc_id     = module.vpc.vpc_id
  cidr_block = var.secondary_cidr_block
}

resource "aws_subnet" "in_secondary_cidr" {
  count      = length(local.azs)
  vpc_id     = aws_vpc_ipv4_cidr_block_association.secondary_cidr.vpc_id
  cidr_block = cidrsubnet(var.secondary_cidr_block, 2, count.index)

  tags = {
    "kubernetes.io/role/cni" = "1"
  }
}
