################################################################################
# EKS Cluster
################################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.5"

  cluster_name                   = local.name
  cluster_version                = "1.29"
  cluster_endpoint_public_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_id = module.vpc.vpc_id
  #subnet_ids = module.vpc.private_subnets
  subnet_ids = slice(module.vpc.private_subnets, 0, 3)

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          # ENABLE_PREFIX_DELEGATION = "true"
          # WARM_PREFIX_TARGET       = "1"
          # ENI_CONFIG_LABEL_DEF    = "topology.kubernetes.io/zone"
          # AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
          ENABLE_SUBNET_DISCOVERY = "true"
        }
      })
    }
    eks-pod-identity-agent = {
      most_recent = true
    }

  }

  enable_cluster_creator_admin_permissions = true
  # access_entries = {
  #   karpenter = {
  #     principal_arn = module.karpenter.node_iam_role_arn
  #     type          = "EC2_LINUX"
  #   }
  # }

  eks_managed_node_group_defaults = {
    ami_type       = "BOTTLEROCKET_x86_64"
    instance_types = ["t3.large", "t3a.large"]

    iam_role_attach_cni_policy = true
  }

  eks_managed_node_groups = {
    bottlerocket = {
      platform   = "bottlerocket"
      subnet_ids = slice(module.vpc.private_subnets, 0, 3)

      min_size     = 1
      max_size     = 5
      desired_size = 3

      ebs_optimized     = true
      enable_monitoring = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
        xvdb = {
          device_name = "/dev/xvdb"
          ebs = {
            encrypted             = true
            kms_key_id            = module.ebs_kms_key.key_arn
            delete_on_termination = true
          }
        }
      }
      iam_role_policy_statements = [
        {
          sid    = "ECRPullThroughCache"
          effect = "Allow"
          actions = [
            "ecr:CreateRepository",
            "ecr:BatchImportUpstreamImage",
          ]
          resources = ["*"]
        }
      ]

      # The following block customize your Bottlerocket user-data, you can comment if you don't need any customizations or add more parameters.
      bootstrap_extra_args = <<-EOT
            [settings.host-containers.admin]
            enabled = false

            [settings.host-containers.control]
            enabled = true

            [settings.kernel]
            lockdown = "integrity"

            [settings.kubernetes.node-labels]
            "bottlerocket.aws/updater-interface-version" = "2.0.0"

            [settings.kubernetes.node-taints]
            "CriticalAddonsOnly" = "true:NoSchedule"

          EOT
    }

    #   additional = {
    #     ami_release_version = "1.20.0-fcf71a47"

    #     # The following specifies a custom ami_id, this can be provided by a data-source. Remove/comment to use the latest Bottlerocket AMI available.
    #     # ami_id = data.aws_ami.eks_bottlerocket.image_id

    #     min_size     = 0
    #     max_size     = 1
    #     desired_size = 0

    #     ebs_optimized     = true
    #     enable_monitoring = true
    #     block_device_mappings = {
    #       xvda = {
    #         device_name = "/dev/xvda"
    #         ebs = {
    #           encrypted             = true
    #           kms_key_id            = module.ebs_kms_key.key_arn
    #           delete_on_termination = true
    #         }
    #       }
    #       xvdb = {
    #         device_name = "/dev/xvdb"
    #         ebs = {
    #           encrypted             = true
    #           kms_key_id            = module.ebs_kms_key.key_arn
    #           delete_on_termination = true
    #         }
    #       }
    #     }
    #     # The following line MUST be true when using a custom ami_id
    #     # use_custom_launch_template = true

    #     # The next line MUST be uncomment when using a custom_launch_template is set to true
    #     # enable_bootstrap_user_data = true

    #     # The following block customize your Bottlerocket user-data, you can comment if you don't need any customizations or add more parameters.
    #     bootstrap_extra_args = <<-EOT
    #           [settings.host-containers.admin]
    #           enabled = false

    #           [settings.host-containers.control]
    #           enabled = true

    #           [settings.kernel]
    #           lockdown = "integrity"

    #           [settings.kubernetes.node-labels]
    #           "bottlerocket.aws/updater-interface-version" = "1.0.0"

    #         EOT
    #   }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}

module "ebs_kms_key" {
  source  = "terraform-aws-modules/kms/aws"
  version = "~> 1.5"

  description = "Customer managed key to encrypt EKS managed node group volumes"

  # Policy
  key_administrators = [
    data.aws_caller_identity.current.arn
  ]

  key_service_roles_for_autoscaling = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
    module.eks.cluster_iam_role_arn,
    module.karpenter.iam_role_arn
  ]

  aliases = ["eks/${local.name}/ebs"]

  tags = local.tags
}
