# k8s/ — raw manifests outside Helm

Everything the application needs is in the Helm chart. These manifests are kept for two reasons: one-off tests, and cluster-wide components that are installed once per cluster rather than per release.

```
k8s/
|-- storage/
|   |-- gp3.yaml                       # first version of the StorageClass (now managed by Helm)
|   `-- smoke-test.yaml                # PVC + pod to test EBS dynamic provisioning
|-- mysql/                             # first plain-manifest MySQL version, replaced by the Helm chart
`-- multus/
    |-- multus-daemonset-thick.yaml    # Multus for EKS, image switched to eu-central-1
    `-- test-pods.yaml                 # two pods attached to the second network
```

## storage/ — EBS smoke test

Checks that the EBS CSI driver can create, attach and delete volumes before deploying the database.

```bash
kubectl apply -f k8s/storage/smoke-test.yaml
kubectl get pvc,pv                          # Bound, a new EBS volume exists
kubectl delete -f k8s/storage/smoke-test.yaml
```

With `reclaimPolicy: Retain` the PV and the EBS volume stay after the PVC is deleted; delete them manually.

## multus/ — second pod network (task 6)

The AWS infrastructure (subnet `10.10.64.0/24`, secondary ENI on node-1) comes from [`modules/multus-net`](../modules/README.md#multus-net). The NetworkAttachmentDefinition comes from the Helm chart. This folder holds the Multus installation and the test pods.

```
pod: eth0 (VPC CNI, 10.10.x.x) ── normal cluster traffic, default route
     net1 (ipvlan on ens7, 10.10.64.11-13) ── 10.10.64.0/24 and 10.20.0.0/16 via 10.10.64.1
```

### Setup

1. **Infrastructure:** apply `live/sbox/multus-net`.

2. **Install Multus.** The AWS manifest points to the us-west-2 ECR registry, which the nodes can't pull from, so the region is replaced:
   ```bash
   curl -sL https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/multus/v4.0.2-eksbuild.1/multus-daemonset-thick.yml \
     | sed 's/us-west-2/eu-central-1/g' > k8s/multus/multus-daemonset-thick.yaml
   kubectl apply -f k8s/multus/multus-daemonset-thick.yaml
   kubectl -n kube-system rollout status ds/kube-multus-ds
   ```

3. **Find the ENI and bring it up on node-1.** A hot-attached ENI starts DOWN; ipvlan needs it UP. `--profile=sysadmin` is needed to change network interfaces.
   ```bash
   NODE=$(kubectl get nodes -l casestudy.io/db-node=node-1 -o name | cut -d/ -f2)
   kubectl debug node/$NODE -it --profile=sysadmin --image=busybox:1.37 -- \
     chroot /host sh -c 'ip -br a; ls /opt/cni/bin | grep -E "ipvlan|host-local"'   # find the interface with 10.10.64.10
   kubectl debug node/$NODE -it --profile=sysadmin --image=busybox:1.37 -- \
     chroot /host sh -c 'ip link set ens7 up; ip -br a show ens7'
   kubectl delete pod -n default $(kubectl get pods -n default -o name | grep node-debugger | cut -d/ -f2)
   ```

4. **NetworkAttachmentDefinition:** set `multus.master` in the chart values to the interface name, then `helm upgrade`.
   ```bash
   kubectl -n casestudy get network-attachment-definitions     # multus-net
   ```

### Test

```bash
kubectl apply -f k8s/multus/test-pods.yaml -n casestudy
kubectl -n casestudy exec multus-a -- ip addr                  # net1: 10.10.64.11/24
kubectl -n casestudy exec multus-a -- ip route                 # 10.20.0.0/16 via 10.10.64.1 dev net1
kubectl -n casestudy exec multus-a -- ping -c 3 10.10.64.12    # pod to pod over net1, 0% loss
kubectl delete -f k8s/multus/test-pods.yaml -n casestudy
```

Any pod can join the network with the annotation `k8s.v1.cni.cncf.io/networks: multus-net` and a nodeSelector for node-1. Pods without the annotation are not affected.

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Multus pods `Init:ImagePullBackOff`, `no basic auth credentials` | Manifest uses the us-west-2 registry | Use the eu-central-1 image (step 2) |
| Pod has only `eth0` | Multus not ready when the pod started | Wait for the DaemonSet, recreate the pod |
| `RTNETLINK answers: Operation not permitted` | Debug pod not privileged | `kubectl debug ... --profile=sysadmin` |
| `net1` exists but no traffic | Parent interface DOWN | `ip link set ens7 up` |
| `ip -br` prints usage | busybox `ip` has no `-br` | Use `ip addr` |

### Limitations

- Single node: only node-1 has the ENI, and the attachment is lost if the node is replaced.
- `ip link set ens7 up` doesn't survive a reboot; production would do this in node bootstrap (launch template user data).
- Fixed IP range (3 pod IPs) with `host-local` IPAM; production would use `whereabouts` plus a controller that assigns pod IPs to the ENI.
- ipvlan pods can't reach their own node over `net1` (expected ipvlan behaviour).
- The ENI uses one of the 3 ENI slots of a `t3.medium`, so node-1 can hold fewer pods.
