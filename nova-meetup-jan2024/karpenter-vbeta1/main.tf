provider "aws" {
  region = local.region
}

# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "${local.region}"]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", "${local.region}"]
  }
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

data "aws_availability_zones" "available" {}

locals {
  name      = basename(path.cwd)
  region    = "us-west-2"
  partition = "aws"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.16"

  cluster_name                   = local.name
  cluster_version                = "1.27"
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Fargate profiles use the cluster primary security group so these are not utilized
  create_cluster_security_group = false
  create_node_security_group    = false

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
  ]

  fargate_profiles = {
    karpenter = {
      selectors = [
        { namespace = "karpenter" }
      ]
    }
    kube_system = {
      name = "kube-system"
      selectors = [
        { namespace = "kube-system" }
      ]
    }
  }

  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        computeType = "Fargate"
        # Ensure that the we fully utilize the minimum amount of resources that are supplied by
        # Fargate https://docs.aws.amazon.com/eks/latest/userguide/fargate-pod-configuration.html
        # Fargate adds 256 MB to each pod's memory reservation for the required nKubernetes
        # components (kubelet, kube-proxy, and containerd). Fargate rounds up to the following
        # compute configuration that most closely matches the sum of vCPU and memory requests in
        # order to ensure pods always have the resources that they need to run.
        resources = {
          limits = {
            cpu = "0.25"
            # We are targetting the smallest Task size of 512Mb, so we subtract 256Mb from the
            # request/limit to ensure we can fit within that task
            memory = "256M"
          }
          requests = {
            cpu = "0.25"
            # We are targetting the smallest Task size of 512Mb, so we subtract 256Mb from the
            # request/limit to ensure we can fit within that task
            memory = "256M"
          }
        }
      })
    }
    vpc-cni    = {}
    kube-proxy = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
  }

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.name
  })
}

################################################################################
# EKS Blueprints Addons
################################################################################

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.12"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_karpenter = true
  karpenter = {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  create_delay_dependencies = [for prof in module.eks.fargate_profiles : prof.fargate_profile_arn]

  helm_releases = {
    kubecost = {
      description      = "A Helm chart for kubecost"
      namespace        = "kubecost"
      create_namespace = true
      chart            = "cost-analyzer"
      chart_version    = "1.106.0"
      repository       = "https://kubecost.github.io/cost-analyzer/"
      set = [
        {
          name  = "kubecostToken"
          value = "aGVsbUBrdWJlY29zdC5jb20=xm343yadf98"
          # },
          # {
          #   name  = "persistentVolume.enabled" # This is just for Demo purposes, since Fargate profiles don't provision storage dynamically.
          #   value = "false"
          # },
          # {
          #   name  = "prometheus.server.persistentVolume.enabled" # This is just for Demo purposes, since Fargate profiles don't provision storage dynamically.
          #   value = "false"
        }
      ]
    }
    gpu-operator = {
      description      = "A Helm chart for NVIDIA GPU operator"
      namespace        = "gpu-operator"
      create_namespace = true
      chart            = "gpu-operator"
      chart_version    = "v23.3.2"
      repository       = "https://nvidia.github.io/gpu-operator"
      values = [
        <<-EOT
          operator:
            defaultRuntime: containerd
        EOT
      ]
    }
  }

  tags = local.tags
}

################################################################################
# Karpenter
################################################################################
resource "kubectl_manifest" "nodepool_default" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  disruption:
    consolidateAfter: 5m0s
    consolidationPolicy: WhenEmpty
    expireAfter: 24h0m0s
  limits:
    cpu: 1k
  template:
    metadata: {}
    spec:
      kubelet:
        maxPods: 110
      nodeClassRef:
        name: default
      requirements:
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values:
        - t
      - key: karpenter.k8s.aws/instance-cpu
        operator: In
        values:
        - "4"
        - "8"
      - key: karpenter.k8s.aws/instance-hypervisor
        operator: In
        values:
        - nitro
      - key: topology.kubernetes.io/zone
        operator: In
        values: ${jsonencode(local.azs)}
      - key: kubernetes.io/arch
        operator: In
        values:
        - amd64
      - key: karpenter.sh/capacity-type
        operator: In
        values:
        - on-demand
      - key: kubernetes.io/os
        operator: In
        values:
        - linux
YAML

  depends_on = [
    module.eks_blueprints_addons,
    kubectl_manifest.ec2nodeclass_default
  ]
}

resource "kubectl_manifest" "nodepool_cpu" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: cost-optimization
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 24h0m0s
  limits:
    cpu: 1k
  template:
    metadata:
      labels:
        kubecon-booth: cost-optimization
    spec:
      kubelet:
        maxPods: 110
      nodeClassRef:
        name: default
      requirements:
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values:
        - c
        - m
      - key: karpenter.k8s.aws/instance-cpu
        operator: In
        values:
        - "8"
        - "16"
        - "32"
      - key: karpenter.k8s.aws/instance-hypervisor
        operator: In
        values:
        - nitro
      - key: topology.kubernetes.io/zone
        operator: In
        values: ${jsonencode(local.azs)}
      - key: kubernetes.io/arch
        operator: In
        values:
        - amd64
      - key: karpenter.sh/capacity-type
        operator: In
        values:
        - on-demand
      - key: kubernetes.io/os
        operator: In
        values:
        - linux
  YAML

  depends_on = [
    module.eks_blueprints_addons,
    kubectl_manifest.ec2nodeclass_default
  ]
}

resource "kubectl_manifest" "nodepool_gpu" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: gpu
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 1h0m0s
  limits:
    cpu: 1k
    memory: 1000Gi
    nvidia.com/gpu: "8"
  template:
    metadata:
      labels:
        kubecon-booth: gpu
    spec:
      nodeClassRef:
        name: gpu
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values:
        - on-demand
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values:
        - g
        - p
      - key: topology.kubernetes.io/zone
        operator: In
        values:
        - us-west-2a
        - us-west-2b
      - key: kubernetes.io/os
        operator: In
        values:
        - linux
      - key: kubernetes.io/arch
        operator: In
        values:
        - amd64
      taints:
      - effect: NoSchedule
        key: nvidia.com/gpu
        value: "true"
  YAML

  depends_on = [
    module.eks_blueprints_addons,
    kubectl_manifest.ec2nodeclass_gpu
  ]
}

resource "kubectl_manifest" "ec2nodeclass_default" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  tags:
    karpenter.sh/discovery: ${module.eks.cluster_name}
YAML

  depends_on = [
    module.eks_blueprints_addons
  ]
}

resource "kubectl_manifest" "ec2nodeclass_gpu" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: gpu
spec:
  amiFamily: AL2
  blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
      encrypted: true
      volumeSize: 100Gi
      volumeType: gp3
  role: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: ${module.eks.cluster_name}
  tags:
    karpenter.sh/discovery: ${module.eks.cluster_name}
YAML

  depends_on = [
    module.eks_blueprints_addons
  ]
}

# Example deployment using the [pause image](https://www.ianlewis.org/en/almighty-pause-container)
# and starts with zero replicas
resource "kubectl_manifest" "karpenter_example_deployment" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: inflate
    spec:
      replicas: 0
      selector:
        matchLabels:
          app: inflate
      template:
        metadata:
          labels:
            app: inflate
        spec:
          terminationGracePeriodSeconds: 0
          containers:
            - name: inflate
              image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
              resources:
                requests:
                  cpu: 1
          nodeSelector:
            kubecon-booth: cost-optimization
  YAML

  # depends_on = [
  #   kubectl_manifest.karpenter_node_template
  # ]
}

resource "kubectl_manifest" "karpenter_example_deployment_gpu" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: gpu 
    spec:
      replicas: 0
      selector:
        matchLabels:
          app: gpu
      template:
        metadata:
          labels:
            app: gpu
        spec:
          terminationGracePeriodSeconds: 0
          containers:
            - name: gpu
              image: "mirantis/gpu-example:cuda-10.2"
              command: ["/bin/sh"]  
              args: ["-c", "while true; do echo hello; sleep 10;done"]
              resources:
                limits:
                  nvidia.com/gpu: "1"
  YAML

  # depends_on = [
  #   kubectl_manifest.karpenter_node_template
  # ]
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-driver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}
