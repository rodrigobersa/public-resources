output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "karpenter" {
  description = "Karpenter settings to be consumed by external modules"
  value       = module.eks_blueprints_addons.karpenter
}