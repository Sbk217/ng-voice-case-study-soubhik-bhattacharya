# 1. IAM role the EBS CSI driver assumes via Pod Identity.
#    Gets the AWS-managed AmazonEBSCSIDriverPolicy (create/attach/delete EBS volumes).
module "ebs_csi_role" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.11.0"

  name                      = "${var.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
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

