################################################################################
# Karpenter
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.24"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

module "karpenter_addon" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.1"

  chart               = "karpenter"
  namespace           = "kube-system"
  description         = "Kubernetes Node Autoscaling: built for flexibility, performance, and simplicity"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart_version       = "1.0.1"
  wait                = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}

################################################################################
# Karpenter resources
################################################################################

resource "helm_release" "karpenter_resources" {
  name  = "karpenter-resources"
  chart = "./karpenter-resources"
  set {
    name  = "ec2nodeclass.securityGroupSelectorTerms.tags"
    value = module.eks.cluster_name
  }
  set {
    name  = "ec2nodeclass.subnetSelectorTerms.tags"
    value = module.eks.cluster_name
  }
  set {
    name  = "ec2nodeclass.tags"
    value = module.eks.cluster_name
  }
  set {
    name  = "ec2nodeclass.role"
    value = split("/", module.karpenter.node_iam_role_arn)[1]
  }
  set {
    name  = "ec2nodeclass.blockDeviceMappings.ebs.kmsKeyID"
    value = module.ebs_kms_key.key_id
  }
  set_list {
    name  = "nodepool.zone"
    value = local.azs
  }

  depends_on = [module.eks_blueprints_addons]
}