################################################################################
# VPC
################################################################################
locals {
  azs = slice(data.aws_availability_zones.azs.names, 0, 4)
  lzs = slice(data.aws_availability_zones.lzs.names, 0, 2)
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
  cidr = var.cidr_block

  azs             = concat(local.azs, local.lzs)
  private_subnets = [for k, v in local.azs : cidrsubnet(var.cidr_block, 4, k)]
  public_subnets = [for k, v in local.azs : cidrsubnet(var.cidr_block, 8, k + 128)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery"          = local.name
    "kubernetes.io/role/internal-elb" = 1
    "kubernetes.io/role/cni"          = "1"

  }

  tags = local.tags
}

resource "aws_subnet" "lzs" {
  for_each = { for k, v in local.lzs : k => v }

  vpc_id            = module.vpc.vpc_id
  cidr_block        = cidrsubnet(module.vpc.vpc_cidr_block, 4, each.key + 4)
  availability_zone = each.value

  tags = merge(local.tags, {
    Name = "${local.name}-${each.value}"
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery"          = local.name
    "kubernetes.io/role/cni"          = "1"
    "kubernetes.io/role/internal-elb" = 1

  })
}

resource "aws_route_table_association" "lzs" {
  for_each       = { for k, v in local.lzs : k => v }
  subnet_id      = aws_subnet.lzs[each.key].id
  route_table_id = module.vpc.private_route_table_ids[0]
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.1"

  vpc_id = module.vpc.vpc_id

  # Security group
  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "elasticloadbalancing", "eks", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service             = service
        subnet_ids          = module.vpc.private_subnets
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}
