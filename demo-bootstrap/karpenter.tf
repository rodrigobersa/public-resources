################################################################################
# Karpenter
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.name
  create_pod_identity_association = true

  # Used to attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

variable "karpenter_crds" {
  type    = list(string)
  default = ["ec2nodeclasses.karpenter.k8s.aws", "nodepools.karpenter.sh", "nodeclaims.karpenter.sh"]
}

resource "kubernetes_labels" "karpenter" {
  for_each = toset(var.karpenter_crds)

  api_version = "apiextensions.k8s.io/v1"
  kind        = "CustomResourceDefinition"
  metadata {
    name = each.key
  }
  labels = {
    "app.kubernetes.io/managed-by" = "Helm"
  }

  force      = true
  depends_on = [helm_release.karpenter-crds]
}

resource "kubernetes_annotations" "karpenter" {
  for_each = toset(var.karpenter_crds)

  api_version = "apiextensions.k8s.io/v1"
  kind        = "CustomResourceDefinition"
  metadata {
    name = each.key
  }
  annotations = {
    "meta.helm.sh/release-name"      = "karpenter-crd"
    "meta.helm.sh/release-namespace" = "kube-system"
  }

  force      = true
  depends_on = [helm_release.karpenter-crds]
}

resource "helm_release" "karpenter-crds" {
  name                = "karpenter-crd"
  description         = "Kubernetes Custom Resource Definitions (CRDs)"
  chart               = "karpenter-crd"
  namespace           = "kube-system"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  version             = "1.14.1"
  wait                = false
}

resource "helm_release" "karpenter" {
  name                = "karpenter"
  description         = "Kubernetes Node Autoscaling: built for flexibility, performance, and simplicity"
  chart               = "karpenter"
  namespace           = "kube-system"
  version             = "1.14.1"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
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
  set = [{
    name  = "ec2nodeclass.securityGroupSelectorTerms.tags"
    value = module.eks.cluster_name
    },
    {
      name  = "ec2nodeclass.subnetSelectorTerms.tags"
      value = module.eks.cluster_name
    },
    {
      name  = "ec2nodeclass.tags"
      value = module.eks.cluster_name
    },
    {
      name  = "ec2nodeclass.role"
      value = split("/", module.karpenter.node_iam_role_arn)[1]
    },
    {
      name  = "ec2nodeclass.blockDeviceMappings.ebs.kmsKeyID"
      value = module.ebs_kms_key.key_id
  }]
  set_list = [{
    name  = "nodepool.zone"
    value = local.azs
  }]

  depends_on = [helm_release.karpenter, helm_release.karpenter-crds]
}