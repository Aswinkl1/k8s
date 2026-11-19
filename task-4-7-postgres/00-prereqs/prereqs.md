# Prerequisites

The cluster is shared. These components were already installed when this task
started, so they are **not reinstalled**. They are recorded here, with pinned
versions, so the setup can be rebuilt from scratch.

| Component | Helm release | Namespace | Chart | App version |
|---|---|---|---|---|
| CloudNativePG operator | `cnpg` | `cnpg-system` | `cnpg/cloudnative-pg` 0.29.2 | 1.30.2 |
| Barman Cloud plugin | `plugin-barman-cloud` | `cnpg-system` | `cnpg/plugin-barman-cloud` 0.9.0 | v0.16.0 |
| cert-manager (needed by the plugin) | `cert-manager` | `cert-manager` | `jetstack/cert-manager` v1.19.1 | v1.19.1 |
| Prometheus, Grafana, Alertmanager | `kube-prometheus-stack` | `observability` | `prometheus-community/kube-prometheus-stack` 86.1.0 | v0.91.0 |

Cluster facts this design depends on:

- 3 worker nodes (k3s v1.34). One Postgres instance per node.
- Default StorageClass `civo-volume` (`WaitForFirstConsumer`, expansion enabled).
- Networking is k3s built-in Flannel plus the k3s NetworkPolicy controller.
- Kyverno enforces: label `app.kubernetes.io/name`, `runAsNonRoot`, no
  privilege escalation, seccomp `RuntimeDefault`, no host namespaces or paths,
  no privileged containers.
- The `observability` Prometheus selects PodMonitors and PrometheusRules from
  every namespace with no label filter.

## Verify (read-only)

```bash
helm list -n cnpg-system
kubectl get pods -n cnpg-system
kubectl get crd | grep -E "cnpg|barmancloud"
kubectl get prometheus -n observability \
  -o custom-columns=NAME:.metadata.name,PODMON:.spec.podMonitorSelector,RULES:.spec.ruleSelector
kubectl get storageclass civo-volume
kubectl get nodes
```

## Rebuild from scratch (only on a fresh cluster)

Do not run this on the shared cluster.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --version v1.19.1 --set crds.enabled=true

helm upgrade --install cnpg cnpg/cloudnative-pg \
  -n cnpg-system --create-namespace --version 0.29.2

helm upgrade --install plugin-barman-cloud cnpg/plugin-barman-cloud \
  -n cnpg-system --version 0.9.0

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n observability --create-namespace --version 86.1.0 \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false
```

## kubectl cnpg plugin (on your laptop)

```bash
kubectl krew install cnpg
kubectl cnpg version
```

## Civo Object Storage bucket

The bucket must be in the **same region** as the cluster (low latency, no
egress cost).

```bash
# Find the cluster region
civo kubernetes ls
civo region ls

# Create the object store (the name becomes the bucket name)
civo objectstore create task-4-7-aswin-pg-backups --size 500 --region <REGION>

# Show it (endpoint and the access key of its credential)
civo objectstore show task-4-7-aswin-pg-backups

# List credentials and print the secret key for the access key
civo objectstore credential ls
civo objectstore credential export --access-key=<ACCESS_KEY>
```

The exact subcommands can differ between Civo CLI versions; check with
`civo objectstore --help`. The same can be done in the Civo dashboard under
**Object Stores**.

Write down:

- bucket name, for example `task-4-7-aswin-pg-backups`
- endpoint, for example `https://objectstore.lon1.civo.com`
- access key and secret key (these go into the secret in step 2, never into a file)

Then edit `03-backup/objectstore.yaml` and replace `<BUCKET>` and `<REGION>`.
