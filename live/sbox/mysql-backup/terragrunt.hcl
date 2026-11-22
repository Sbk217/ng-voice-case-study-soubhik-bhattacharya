include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}
terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/mysql-backup"
}
dependency "eks" {
  config_path = "../eks"
  mock_outputs = { cluster_name = "eks-mock" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}
inputs = {
  cluster_name = dependency.eks.outputs.cluster_name
}