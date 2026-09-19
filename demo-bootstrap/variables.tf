variable "cluster_version" {
  description = "Amazon EKS Kubernetes version. Defaults to `1.36`"
  type        = string
  default     = "1.36"
}

variable "aws_lbc_version" {
  description = "AWS Load Balancer Controller chart version, also used to fetch the matching reference IAM policy (chart `x.y.z` ships controller `vx.y.z`). Defaults to `3.5.0`"
  type        = string
  default     = "3.5.0"
}