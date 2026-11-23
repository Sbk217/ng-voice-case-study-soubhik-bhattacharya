include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/modules/multus-net"
}

dependency "eks" {
  config_path                             = "../eks"
  mock_outputs                            = { cluster_name = "eks-mock" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id                                = "vpc-00000000"
    private_route_table_ids               = ["rtb-00000000"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  cluster_name            = dependency.eks.outputs.cluster_name
  vpc_id                  = dependency.vpc.outputs.vpc_id
  private_route_table_ids = dependency.vpc.outputs.private_route_table_ids
  device_index            = 2
}