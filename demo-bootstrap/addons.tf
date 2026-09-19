data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

locals {
  aws_load_balancer_controller_service_account = "aws-load-balancer-controller"
}

data "http" "aws-load-balancer-controller-policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/tags/v${var.aws_lbc_version}/docs/install/iam_policy.json"

  request_headers = {
    Accept = "application/json"
  }

  # A non-2xx response is not an error for this data source, so without this the
  # response body ("404: Not Found") reaches IAM and fails as a malformed policy
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Failed to fetch the AWS Load Balancer Controller IAM policy for v${var.aws_lbc_version}: HTTP ${self.status_code}"
    }
  }
}

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${local.name}-aws-load-balancer-controller"
  description = "Dynamic IAM policy for the AWS Load Balancer Controller on ${local.name}"
  policy      = data.http.aws-load-balancer-controller-policy.response_body

  tags = local.tags
}

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "${local.name}-aws-load-balancer-controller"
  description        = "EKS Pod Identity role for the AWS Load Balancer Controller on ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.addon_pod_identity_trust.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  role       = aws_iam_role.aws_load_balancer_controller.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

resource "aws_eks_pod_identity_association" "aws_load_balancer_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = local.aws_load_balancer_controller_service_account
  role_arn        = aws_iam_role.aws_load_balancer_controller.arn

  tags = local.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  name        = "aws-load-balancer-controller"
  description = "A Helm chart to deploy aws-load-balancer-controller for ingress resources"
  chart       = "aws-load-balancer-controller"
  namespace   = "kube-system"
  version     = var.aws_lbc_version
  repository  = "https://aws.github.io/eks-charts"
  wait        = false

  set = [{
    name  = "clusterName"
    value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.name"
      value = local.aws_load_balancer_controller_service_account
    },
    {
      name  = "tolerations[0].key"
      value = "CriticalAddonsOnly"
    },
    {
      name  = "tolerations[0].operator"
      value = "Exists"
    },
    {
      name  = "enableServiceMutatorWebhook"
      value = "false"
    },
    {
      name  = "podDisruptionBudget.maxUnavailable"
      value = "1"
  }]

  depends_on = [
    module.eks,
    aws_eks_pod_identity_association.aws_load_balancer_controller,
  ]
}

resource "helm_release" "bottlerocket_shadow" {
  name             = "brupop-crd"
  description      = "CRDs for Bottlerocket Update Operator"
  chart            = "bottlerocket-shadow"
  namespace        = "brupop-bottlerocket-aws"
  create_namespace = true
  version          = "1.0.0"
  repository       = "https://bottlerocket-os.github.io/bottlerocket-update-operator/"
  wait             = false

  depends_on = [module.eks]
}

resource "helm_release" "bottlerocket_update_operator" {
  name             = "brupop-operator"
  description      = "A Helm chart for Bottlerocket Update Operator"
  chart            = "bottlerocket-update-operator"
  namespace        = "brupop-bottlerocket-aws"
  create_namespace = true
  version          = "1.8.0"
  repository       = "https://bottlerocket-os.github.io/bottlerocket-update-operator/"
  wait             = false

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
  }]

  depends_on = [helm_release.bottlerocket_shadow]
}
