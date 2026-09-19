data "aws_iam_policy_document" "addon_pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

locals {
  addon_iam_roles = {
    aws-ebs-csi-driver = {
      policy_arns = ["arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"]
    }
    aws-efs-csi-driver = {
      policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"]
    }
    aws-fsx-csi-driver = {
      policy_arns = ["arn:aws:iam::aws:policy/AmazonFSxFullAccess"]
    }
    amazon-cloudwatch-observability = {
      policy_arns = [
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
        "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
      ]
    }
    aws-network-flow-monitoring-agent = {
      policy_arns = ["arn:aws:iam::aws:policy/CloudWatchNetworkFlowMonitorAgentPublishPolicy"]
    }
  }

  # "<addon>/<policy name>" => { addon, policy_arn }, so each attachment is a
  # distinct for_each key
  addon_iam_role_policies = merge([
    for addon, config in local.addon_iam_roles : {
      for policy_arn in config.policy_arns :
      "${addon}/${basename(policy_arn)}" => {
        addon      = addon
        policy_arn = policy_arn
      }
    }
  ]...)
}

resource "aws_iam_role" "addon" {
  for_each = local.addon_iam_roles

  name               = "${local.name}-${each.key}"
  description        = "EKS Pod Identity role for the ${each.key} addon on ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.addon_pod_identity_trust.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "addon" {
  for_each = local.addon_iam_role_policies

  role       = aws_iam_role.addon[each.value.addon].name
  policy_arn = each.value.policy_arn
}

# The EBS CSI driver needs to use the customer managed key whenever a
# StorageClass (or the node volumes it snapshots/restores) is encrypted with it.
# The managed policy only covers the EC2 API calls.
data "aws_iam_policy_document" "ebs_csi_kms" {
  statement {
    effect    = "Allow"
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = [module.ebs_kms_key.key_arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [module.ebs_kms_key.key_arn]
  }
}

resource "aws_iam_role_policy" "ebs_csi_kms" {
  name   = "kms"
  role   = aws_iam_role.addon["aws-ebs-csi-driver"].id
  policy = data.aws_iam_policy_document.ebs_csi_kms.json
}
