# Demo Bootstrap

## Environment Provisioning

```bash
terraform fmt -recursive \
terraform init -upgrade \
terraform plan 
```

Sample output (truncated for brevity)

```output
... truncated for brevity

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.

... truncated for brevity
Plan: 107 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply -target module.vpc -auto-approve \
terraform apply -target module.eks -target module.karpenter -auto-approve \
terraform apply -auto-approve
```

## Environment Cleanup

```bash
terraform destroy -target helm_release.karpenter_resources -auto-approve \
terraform destroy -target module.eks_blueprints_addons -target module.karpenter_addon -auto-approve \
terraform destroy -target module.eks -target module.karpenter -auto-approve \
terraform destroy -auto-approve
```
