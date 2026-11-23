# live/ — Terragrunt environments

Each folder under `live/<env>/` is one **unit** (one Terraform state). Units only say *which* module to use and *which* inputs to pass; the logic lives in registry modules or in [`modules/`](../modules/README.md).

```
live/sbox/
|-- env.hcl          # values that differ per environment
|-- vpc/             # terraform-aws-modules/vpc        6.7.3
|-- eks/             # terraform-aws-modules/eks        21.30.2
|-- eks-addons/      # modules/eks-addons   (EBS CSI driver, AWS Load Balancer Controller)
|-- mysql-backup/    # modules/mysql-backup (S3 bucket + IAM role for backups)
`-- multus-net/      # modules/multus-net   (subnet + secondary ENI for task 6)
```

## How the pieces fit

| File | Responsibility |
|------|----------------|
| `../../root.hcl` | S3 remote state (`tfstate-casestudy-<account-id>`, encrypted, native lockfile), generated AWS provider with default tags (`app`, `env`, `terraform`), common inputs `env`, `region`, `app` |
| `env.hcl` | CIDRs, AZs, EKS version, node sizes, admin role ARN, allowed IP |
| `<unit>/terragrunt.hcl` | `include "root"`, `terraform.source`, `dependency` blocks, `inputs` |

```
vpc ──► eks ──► eks-addons
          ├───► mysql-backup
vpc ──────┴───► multus-net
```

- `dependency` blocks pass outputs between units (e.g. `vpc_id`, `cluster_name`).
- `mock_outputs` are allowed only for `init`, `validate` and `plan`, so a unit can be planned before its upstream exists but never applied with fake IDs.
- Registry modules are pinned to exact versions; `.terraform.lock.hcl` files are committed.

## Key design decisions (sbox)

| Setting | Value | Why |
|---------|-------|-----|
| VPC CIDR | `10.10.0.0/16` | Largest VPC; primary CIDR can't be resized. Plan per env: sbox 10.10, dev 10.20, ... |
| AZs | 3 | Survives one AZ loss; EBS is AZ-bound |
| Private subnets | 3 x `/20` | VPC CNI gives every pod a VPC IP; room for scaling and node rotation |
| Public subnets | 3 x `/24` | Only ALB ENIs and the NAT gateway |
| NAT | single | Cost saving in sbox; prod: one per AZ |
| Task 6 subnet | `10.10.64.0/24` | From the unused range above the public subnets |
| EKS version | 1.37 | Standard support (extended support costs 6x) |
| Nodes | AL2023, 3 x `t3.medium` (min 3, max 4) | 3 nodes needed for task 7 |
| API endpoint | public, restricted to my `/32` | kubectl from the laptop |
| Access | `authentication_mode = API`, access entry for the SSO admin role | Admins declared in code, not "whoever ran apply" |

## Apply

```bash
export AWS_PROFILE=casestudy
aws sso login --profile casestudy

# first time only: create the S3 state bucket
cd live/sbox/vpc && terragrunt backend bootstrap && cd ..

# everything, in dependency order
terragrunt run --all plan
terragrunt run --all apply
```

Single unit, with a saved plan so exactly the reviewed plan is applied:

```bash
cd live/sbox/<unit>
terragrunt plan -out=tfplan
terragrunt apply tfplan
```

After `mysql-backup`, copy the bucket name into `charts/case-study/charts/mysql/values.yaml`:

```bash
cd live/sbox/mysql-backup && terragrunt output -raw bucket_name
```

Before `multus-net`, check which ENI device index is free on node-1 (the VPC CNI usually uses 0 and 1):

```bash
aws ec2 describe-instances --filters "Name=availability-zone,Values=eu-central-1a" "Name=tag:eks:cluster-name,Values=eks-casestudy-sbox-01" \
  --query 'Reservations[].Instances[].NetworkInterfaces[].Attachment.DeviceIndex'
```

## Formatting

```bash
terragrunt hcl format          # .hcl files
terraform fmt -recursive       # .tf files in modules/
```

## Troubleshooting

| Error | Fix |
|-------|-----|
| `no EC2 IMDS role found` / `get_aws_account_id` fails | `export AWS_PROFILE=casestudy`; run `aws sso login` if the token expired |
| `bucket does not exist` | `terragrunt backend bootstrap` |
| `explicit deny ... service control policy` | An org SCP blocks the region; IAM calls are evaluated in us-east-1 |

## Teardown

Kubernetes-created AWS resources (ALB, EBS volumes) must go first, otherwise the VPC destroy fails and retained volumes keep costing money.

```bash
kubectl delete -f k8s/multus/test-pods.yaml -n casestudy --ignore-not-found
helm uninstall case-study -n casestudy            # removes the ALB
kubectl delete pvc --all -n casestudy
# delete the Released PVs and their EBS volumes (reclaimPolicy: Retain)

cd live/sbox
terragrunt run --all destroy                      # reverse order: multus-net, mysql-backup, eks-addons, eks, vpc
aws ecr delete-repository --repository-name pod-monitor --force --region eu-central-1
```
