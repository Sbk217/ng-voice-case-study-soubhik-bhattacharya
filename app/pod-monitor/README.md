# pod-monitor — Go pod event logger

Watches pods in a namespace and logs one JSON line per event: created, updated, deleted.

## How it works

- **SharedInformer** (client-go): lists pods once, then watches. Reconnects automatically and keeps a local cache, instead of polling the API.
- **Events:**
  - `pod existing` — pods already present at startup (`isInInitialList`), so they aren't reported as new
  - `pod created`
  - `pod updated` — old/new phase, readiness, node, pod IP; periodic resyncs (same `ResourceVersion`) are skipped
  - `pod deleted` — also handles `DeletedFinalStateUnknown` (deletion missed while disconnected)
- **Config:** in-cluster service account when running as a pod, `~/.kube/config` when run locally.
- **Scope:** `WATCH_NAMESPACE`; empty means all namespaces.
- **Shutdown:** graceful on SIGINT / SIGTERM.

Example log line:

```json
{"time":"2026-11-23T08:52:10Z","level":"INFO","msg":"pod updated","namespace":"casestudy","pod":"web-6d9f7c8b5-25gxj","oldPhase":"Pending","newPhase":"Running","ready":true,"node":"ip-10-10-25-43.eu-central-1.compute.internal","podIP":"10.10.21.7"}
```

## Run locally

```bash
cd app/pod-monitor
go mod tidy
WATCH_NAMESPACE=casestudy go run .
# in another terminal: kubectl delete pod -n casestudy <a-web-pod>
# stop with Ctrl+C
```

## Build and push the image

Multi-stage build: static binary (`CGO_ENABLED=0`), final image `gcr.io/distroless/static:nonroot` (no shell, uid 65532). Built for `linux/amd64` because the nodes are x86 (needed when building on an Apple Silicon Mac).

Due to constraint of time had to se normal push to the container registry rather than sing a CD pipeline.

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text); REGION=eu-central-1
REPO=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/pod-monitor

aws ecr create-repository --repository-name pod-monitor --region $REGION \
  --image-scanning-configuration scanOnPush=true          # first time only
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
docker buildx build --platform linux/amd64 -t $REPO:0.1.0 --push .
```

Bump the tag for every new build and set it in `charts/case-study/charts/pod-monitor/values.yaml`.

## Deploy

Deployed by the umbrella chart (`pod-monitor.enabled: true`). The chart creates:
- ServiceAccount + Role (`get`, `list`, `watch` on pods in its namespace only) + RoleBinding
- Deployment with `runAsUser: 65532`, read-only root filesystem, all capabilities dropped

## Verify

```bash
kubectl logs -n casestudy deploy/pod-monitor -f
kubectl delete pod -n casestudy <a-web-pod>     # -> updated, deleted, created, updated ... ready=true
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `CreateContainerConfigError: non-numeric user (nonroot)` | `runAsNonRoot` needs a numeric UID: set `runAsUser: 65532` |
| `exec format error` | Image built for arm64; rebuild with `--platform linux/amd64` |
| `forbidden: cannot list pods` | Role/RoleBinding missing or `WATCH_NAMESPACE` points to another namespace |
