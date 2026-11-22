locals {
  env = "sbox"
  region = "eu-central-1"

  vpc = {
    cidr               = "10.10.0.0/16" //max VPC size; primary CIDR can't be resized later. sbox gets 10.10, dev gets 10.20 qa and prod henceforth.
    azs                = ["eu-central-1a", "eu-central-1b", "eu-central-1c"] // selecting 3 AZ as surviving AZ loss is more than selecting 2.
    private_subnets    = ["10.10.0.0/20", "10.10.16.0/20", "10.10.32.0/20"] //around 4k address usable for each subnets in the 3 AZs and 5 reserved for AWS use. leaves room for autoscaling and node rotation during upgrades, when old and new nodes run side by side
    public_subnets     = ["10.10.48.0/24", "10.10.49.0/24", "10.10.50.0/24"] //Only the ALB/NLB ENIs and the NAT gateway live here. Pods and nodes don’t. thus 251 usable each is more than enough.
    single_nat_gateway = true   # dev: save cost; prod: one per AZ
  }

  eks = {
    version = "1.37" //in standard support ($0.10/h); extended-support versions cost $0.60/h
    endpoint_public_access_cidrs = ["80.88.28.130/32"]
    admin_role_arn = "arn:aws:iam::966454767733:role/aws-reserved/sso.amazonaws.com/eu-central-1/AWSReservedSSO_AdministratorAccess_82a3c2445f0599d7"
    node_group = {
      instance_types = ["t3.medium"]
      min_size       = 3
      desired_size   = 3
      max_size       = 4
      disk_size      = 20
    }
  }

}