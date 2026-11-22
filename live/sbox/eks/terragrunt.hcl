include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws?version=21.30.2"
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  eks      = local.env_vars.locals.eks
  name     = "eks-${include.root.locals.app}-${include.root.locals.env}-01"
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id          = "vpc-00000000"
    private_subnets = ["subnet-aaaa", "subnet-bbbb", "subnet-cccc"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"] //for testing only
}

inputs = {
  name                                     = local.name
  kubernetes_version                       = local.eks.version

  vpc_id                                   = dependency.vpc.outputs.vpc_id
  subnet_ids                               = dependency.vpc.outputs.private_subnets   # nodes in private subnets only

  endpoint_public_access                   = true   # for accessing kubectl from my laptop
  endpoint_public_access_cidrs             = local.eks.endpoint_public_access_cidrs

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    sso_admin = {
      principal_arn = local.eks.admin_role_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  cloudwatch_log_group_retention_in_days = 7


  addons = {
    vpc-cni = {
      before_compute                       = true
      configuration_values                 = jsonencode({ enableNetworkPolicy = "true" })  # for task 4
    }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
  }

  eks_managed_node_groups = {
    general = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = local.eks.node_group.instance_types
      min_size       = local.eks.node_group.min_size
      desired_size   = local.eks.node_group.desired_size
      max_size       = local.eks.node_group.max_size
    }
  }
}