include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=6.7.3"
}


locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  vpc      = local.env_vars.locals.vpc
  name     = "vpc-${include.root.locals.app}-${include.root.locals.env}-01"
}





inputs = {
  name               = local.name
  cidr               = local.vpc.cidr
  azs                = local.vpc.azs

  private_subnets    = local.vpc.private_subnets
  public_subnets     = local.vpc.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = local.vpc.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support = true

  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }

}