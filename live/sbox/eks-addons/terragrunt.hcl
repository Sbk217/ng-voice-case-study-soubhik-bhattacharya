//MYSQL requires EBS volumes so EBS CSI driver is required. It calls the

include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/eks-addons"
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = { vpc_id = "vpc-00000000" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    cluster_name                       = "eks-mock"
    cluster_version                    = "1.37"
    cluster_endpoint                   = "https://mock"
    cluster_certificate_authority_data = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name       = dependency.eks.outputs.cluster_name
  kubernetes_version = dependency.eks.outputs.cluster_version
  cluster_endpoint   = dependency.eks.outputs.cluster_endpoint
  cluster_ca_data    = dependency.eks.outputs.cluster_certificate_authority_data
  vpc_id             = dependency.vpc.outputs.vpc_id
  region             = include.root.locals.region
}