# 1. IAM role the EBS CSI driver assumes via Pod Identity.
#    Gets the AWS-managed AmazonEBSCSIDriverPolicy (create/attach/delete EBS volumes).
module "ebs_csi_role" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.11.0"

  name                      = "${var.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
}

# IAM role for the controller (ELB, target groups, security groups), via Pod Identity
module "lbc_role" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.11.0"

  name                            = "${var.cluster_name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    lbc = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

# 2. Latest add-on version compatible with the cluster's Kubernetes version.
data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

# 3. Install the driver and bind its controller service account to the role.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  resolve_conflicts_on_update = "OVERWRITE"

  pod_identity_association {
    role_arn        = module.ebs_csi_role.iam_role_arn
    service_account = "ebs-csi-controller-sa"
  }
}


# page had to be reachable from a browser, and the pods sit in private subnets. On EKS, the native way is an Ingress handled by the AWS Load Balancer Controller, the Service is as ClusterIP which restricts access to pod IP, and uses no Service of type LoadBalancer.
resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.3"
  namespace  = "kube-system"

  set = [
    { name = "clusterName", value = var.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = var.vpc_id },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
  ]

  depends_on = [module.lbc_role]
}

