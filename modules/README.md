# modules/ — own Terraform modules

Reusable logic only. Modules know nothing about environments; all values come from the Terragrunt units in [`live/`](../live/README.md). Each module splits its code into `main.tf`, `variables.tf` and, where needed, `outputs.tf` and a provider versions file.

| Module | Creates | Used by |
|--------|---------|---------|
| [`eks-addons`](#eks-addons) | EBS CSI driver, AWS Load Balancer Controller, their IAM roles | `live/sbox/eks-addons` |
| [`mysql-backup`](#mysql-backup) | S3 backup bucket, IAM role, Pod Identity association | `live/sbox/mysql-backup` |
| [`multus-net`](#multus-net) | Subnet, security group and secondary ENI for task 6 | `live/sbox/multus-net` |

## eks-addons

| Resource | Purpose |
|----------|---------|
| `module.ebs_csi_role` (eks-pod-identity 2.11.0) | IAM role with `AmazonEBSCSIDriverPolicy`, trusted by `pods.eks.amazonaws.com` |
| `data.aws_eks_addon_version` + `aws_eks_addon.ebs_csi` | Latest compatible EBS CSI add-on, bound to the role via `pod_identity_association` |
| `module.lbc_role` | IAM role for the AWS Load Balancer Controller, associated with `kube-system/aws-load-balancer-controller` |
| `helm_release.aws_lbc` | AWS Load Balancer Controller chart 3.6.3 from `eks-charts` |

- `helm-provider.tf` configures the Helm provider against the cluster with `aws eks get-token` (named so it doesn't clash with Terragrunt's generated `provider.tf`).
- The Load Balancer Controller turns the web Ingress into an ALB. It was chosen over ingress-nginx, which was retired in March 2026.

| Input | Description |
|-------|-------------|
| `cluster_name`, `kubernetes_version`, `region`, `vpc_id` | From the `eks`/`vpc` units |
| `cluster_endpoint`, `cluster_ca_data` | For the Helm provider |

Output: `ebs_csi_role_arn`.

## mysql-backup

| Resource | Purpose |
|----------|---------|
| `aws_s3_bucket.backup` | `<cluster>-mysql-backup-<random>`, `force_destroy` for easy teardown |
| versioning, SSE (AES256), public access block | Backups are versioned, encrypted, never public |
| lifecycle rule | Current and old versions expire after `retention_days` |
| `aws_iam_role.backup` | Trusted only by `pods.eks.amazonaws.com` (Pod Identity) |
| `aws_iam_role_policy.backup` | Least privilege: `PutObject`/`GetObject` on objects, `ListBucket` on this bucket only |
| `aws_eks_pod_identity_association.backup` | Binds `casestudy/mysql-backup` to the role |

| Input | Default |
|-------|---------|
| `cluster_name` | (required) |
| `namespace` | `casestudy` |
| `service_account` | `mysql-backup` |
| `retention_days` | `14` |

Outputs: `bucket_name` (goes into the mysql chart values), `role_arn`.

## multus-net

Infrastructure for the second pod network (task 6).

| Resource | Purpose |
|----------|---------|
| `data.aws_instances.node1` | The running cluster node in eu-central-1a (node-1) |
| `aws_subnet.multus` | `10.10.64.0/24` in eu-central-1a, associated with the private route table |
| `aws_security_group.multus` | All traffic from the VPC in, all out |
| `aws_network_interface.multus` | ENI with `.10` (primary) and `.11-.13` reserved for pods, tagged `node.k8s.amazonaws.com/no_manage = true` so the VPC CNI leaves it alone |
| `aws_network_interface_attachment.multus` | Attaches the ENI to node-1 at `device_index` |

| Input | Description |
|-------|-------------|
| `cluster_name`, `vpc_id`, `private_route_table_ids` | From the `eks`/`vpc` units |
| `device_index` | Free ENI slot on node-1 (default 2; 0 and 1 are usually taken by the VPC CNI) |

**Why the pod IPs are on the ENI:** with ipvlan the pods send traffic from their own IPs. The VPC only accepts traffic from IPs it knows on that ENI, so the pod IPs must be assigned as secondary IPs.

**Limitations:** single node; the attachment is lost if node-1 is replaced. In production, add the ENI through the node group's launch template plus an ASG lifecycle hook, and manage pod IPs dynamically (`whereabouts` + an IP-assignment controller).
