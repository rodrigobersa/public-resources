################################################################################
# EKS Blueprints Addons
################################################################################
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.15"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    set = [{
      name  = "tolerations[0].key"
      value = "CriticalAddonsOnly"
      },
      {
        name  = "tolerations[0].operator"
        value = "Exists"
    }]
  }

  # enable_aws_node_termination_handler   = true
  # aws_node_termination_handler_asg_arns = ["arn:aws:autoscaling:us-west-2:748406189247:autoScalingGroup:2d96cf2f-9e5a-4644-8d69-eb55224a714f:autoScalingGroupName/eks-bottlerocket-20240729162709915600000008-d8c87fa8-99ef-6872-ba97-df57f983188b"]

  enable_cert_manager = true
  cert_manager = {
    wait          = true
    wait_for_jobs = true
    set = [{
      name  = "tolerations[0].key"
      value = "CriticalAddonsOnly"
      },
      {
        name  = "tolerations[0].operator"
        value = "Exists"
      },
      {
        name  = "cainjector.tolerations[0].key"
        value = "CriticalAddonsOnly"
      },
      {
        name  = "cainjector.tolerations[0].operator"
        value = "Exists"
      },
      {
        name  = "webhook.tolerations[0].key"
        value = "CriticalAddonsOnly"
      },
      {
        name  = "webhook.tolerations[0].operator"
        value = "Exists"
      },
      {
        name  = "startupapicheck.tolerations[0].key"
        value = "CriticalAddonsOnly"
      },
      {
        name  = "startupapicheck.tolerations[0].operator"
        value = "Exists"
    }]
  }

  # enable_karpenter = true
  # karpenter = {
  #   repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  #   repository_password = data.aws_ecrpublic_authorization_token.token.password
  #   chart_version       = "1.0.1"
  #   namespace           = "kube-system"
  #   create_namespace    = false
  # }

  bottlerocket_shadow = {
    name = "brupop-crd"
  }
  enable_bottlerocket_update_operator = true
  bottlerocket_update_operator = {
    set = [{
      name  = "scheduler_cron_expression"
      value = "* * * * * * *" # Default Unix Cron syntax, set to check every hour. Example "0 0 23 * * Sat *" Perform update checks every Saturday at 23H / 11PM
      },
      {
        name  = "placement.agent.tolerations[0].key"
        value = "CriticalAddonsOnly"
      },
      {
        name  = "placement.agent.tolerations[0].operator"
        value = "Exists"
      },
      {
        name  = "placement.controller.tolerations[0].key"
        value = "CriticalAddonsOnly"
      },
      {
        name  = "placement.controller.tolerations[0].operator"
        value = "Exists"
      },
      {
        name  = "placement.apiserver.tolerations[0].key"
        value = "CriticalAddonsOnly"
      },
      {
        name  = "placement.apiserver.tolerations[0].operator"
        value = "Exists"
      }
    ]
  }

  tags = local.tags
}
