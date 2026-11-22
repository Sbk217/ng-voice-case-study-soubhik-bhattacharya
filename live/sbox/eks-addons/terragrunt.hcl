//MYSQL requires EBS volumes so EBS CSI driver is required. It calls the

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/eks-addons"
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    cluster_name    = "eks-mock"
    cluster_version = "1.37"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name       = dependency.eks.outputs.cluster_name
  kubernetes_version = dependency.eks.outputs.cluster_version
}