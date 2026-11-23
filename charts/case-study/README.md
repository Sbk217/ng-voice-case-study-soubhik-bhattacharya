# charts/case-study — Helm master chart

One release (`case-study`, namespace `casestudy`) deploys every application component. Each component is a subchart that can be switched off with `<name>.enabled: false`.

```
charts/case-study/
|-- Chart.yaml                  # dependencies: mysql, web, pod-monitor (condition: <name>.enabled)
|-- values.yaml                 # defaults + per-subchart switches
|-- values-sbox.yaml            # environment overrides (currently empty)
|-- templates/
|   |-- storageclass.yaml       # gp3 StorageClass (default)
|   `-- multus-nad.yaml         # NetworkAttachmentDefinition for task 6
`-- charts/
    |-- mysql/                  # tasks 2, 4, 5, 7
    |-- web/                    # task 3
    `-- pod-monitor/            # part 2
```

## Install / upgrade

```bash
helm lint charts/case-study
helm template case-study charts/case-study -n casestudy | less        # render without applying
helm upgrade --install case-study charts/case-study -n casestudy --create-namespace
kubectl get pods,svc,ingress -n casestudy
```

> Use `--reset-values` on an upgrade after you used `--set`. Otherwise Helm reuses the old `--set` values (e.g. a restore runs again).

## master values

| Key | Default | Description |
|-----|---------|-------------|
| `storageClass.name` / `type` / `reclaimPolicy` | `gp3` / `gp3` / `Retain` | EBS StorageClass; `Retain` keeps the disk when a PVC is deleted |
| `mysql.enabled`, `web.enabled`, `pod-monitor.enabled` | `true` | Subchart switches |
| `multus.enabled` | `true` | Render the NetworkAttachmentDefinition (Multus must be installed, see [k8s/](../../k8s/README.md)) |
| `multus.umbrella` | `ens7` | Host interface of the secondary ENI on node-1 |

## mysql subchart

Templates: `secret`, `configmap` (cnf files + init scripts), headless `service`, `statefulset` (one per member), `networkpolicy`, `backup-serviceaccount`, `backup-cronjob`, `restore-job`.

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` / `tag` | `mysql` / `8.4` | Official image, LTS |
| `members[]` | `db-x` primary on `[node-1]`, `db-y` replica on `[node-2, node-3]` | One StatefulSet per member; `nodes` matches node label `casestudy.io/db-node` (task 7) |
| `storage.className` / `size` | `gp3` / `10Gi` | PVC per member |
| `networkPolicy.allowedApps` | `[web, mysql, mysql-backup]` | `app` labels allowed on TCP 3306 (task 4) |
| `backup.enabled` / `schedule` | `true` / `0 2 * * *` | Daily backup CronJob (UTC) |
| `backup.bucket` | from `terragrunt output bucket_name` | S3 bucket |
| `backup.sourceHost` | `db-y-0.mysql` | Dump from the replica |
| `backup.databases` | `[demo]` | Databases to dump |
| `restore.enabled` / `file` | `false` / `""` | Opt-in restore Job |
| `restore.targetHost` | `db-x-0.mysql` | Always restore into the primary |

How it works:
- **Secret** `mysql-auth` (root + replication password) is generated once with `randAlphaNum`, reused on upgrades via `lookup`, and kept on uninstall (`helm.sh/resource-policy: keep`).
- **Replication** is configured on the first start only: an init container writes `server-id = 100 + member index` and copies the role's `.cnf` and init script into `/docker-entrypoint-initdb.d`.
- **Probes:** readiness over TCP (only passes on the real server), liveness over the socket (never kills MySQL during first init).

### Backup

```bash
kubectl create job --from=cronjob/mysql-backup backup-manual-1 -n casestudy
kubectl logs -n casestudy job/backup-manual-1 -c upload       # shows the S3 key
```

### Restore

```bash
helm upgrade case-study charts/case-study -n casestudy \
  --set mysql.restore.enabled=true --set mysql.restore.file=mysql/<timestamp>.sql
kubectl logs -n casestudy job/mysql-restore-<revision> -c restore     # "restore done"
helm upgrade case-study charts/case-study -n casestudy --reset-values  # switch restore off again
```

The Job is named `mysql-restore-<Helm revision>`, so each restore gets a fresh Job.

## web subchart

Templates: `configmap` (`default.conf`, `index.html.tpl`), `deployment`, `service` (ClusterIP), `ingress` (ALB).

| Key | Default | Description |
|-----|---------|-------------|
| `replicas` | `3` | |
| `image` | `nginx/nginx-unprivileged:1.31.9-alpine3.24` | uid 101, port 8080 |
| `initImage` | `busybox:1.37` | Renders `index.html` |
| `ingress.enabled` | `true` | Creates the ALB via the AWS Load Balancer Controller |
| `ingress.allowedCidrs` | `[80.88.28.130/32]` | Who may reach the ALB; add your current IP here |

How it works:
- The init container reads `POD_NAME` / `POD_IP` from the Downward API, replaces `__POD_IP__` and `__SERVING_HOST__` (-> `Host-<last 5 chars of pod name>`) and writes `index.html` to a shared `emptyDir`.
- `default.conf` is mounted via `subPath`; a `checksum/config` annotation rolls the pods when the ConfigMap changes (subPath mounts don't update on their own).
- Ingress annotations: `scheme: internet-facing`, `target-type: ip` (ALB sends traffic straight to pod IPs), `healthcheck-path: /healthz`, `inbound-cidrs`.

## pod-monitor subchart

Templates: `rbac` (ServiceAccount, Role with `get/list/watch` on pods, RoleBinding), `deployment`.

| Key | Default |
|-----|---------|
| `image.repository` / `tag` | `<account>.dkr.ecr.eu-central-1.amazonaws.com/pod-monitor` / `0.1.0` |
| `resources` | requests 10m / 32Mi, limit 64Mi |

`WATCH_NAMESPACE` is set from the pod's own namespace. Runs as uid 65532 with a read-only root filesystem. Source and build: [app/pod-monitor/](../../app/pod-monitor/README.md).

## Template conventions

- `_helpers.tpl` per subchart: full labels for metadata, a minimal selector label (`app: <name>`), because selectors are immutable.
- `nindent N`: N = indentation of the key + 2.
- Go template comments `{{- /* ... */ -}}` instead of YAML comments in templates.

## Adopting existing resources

Resources first created with `kubectl` (e.g. the `gp3` StorageClass) can be taken over by the release:

```bash
kubectl label storageclass gp3 app.kubernetes.io/managed-by=Helm
kubectl annotate storageclass gp3 meta.helm.sh/release-name=case-study meta.helm.sh/release-namespace=casestudy
```
