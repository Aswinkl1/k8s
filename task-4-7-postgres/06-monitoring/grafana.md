# Grafana

The dashboards come from the shared `observability` kube-prometheus-stack,
which already scrapes this cluster through the PodMonitors in this folder.

## Open Grafana

```bash
kubectl get svc -n observability | grep grafana
kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80
```

Open http://localhost:3000. If you don't have the login, ask the cluster
admin; the admin password is usually in the secret
`kube-prometheus-stack-grafana` (key `admin-password`), which you may not be
allowed to read.

## Import the CNPG dashboard

1. **Dashboards → New → Import**
2. Dashboard ID **20417** (CloudNativePG, published by the CNPG project) → **Load**
3. Data source: the Prometheus data source → **Import**
4. At the top, pick namespace `aswin-kl` and cluster `task-4-7-aswin-pg`

Panels worth showing in the demo:

- Instance status and the current primary
- Replication lag per replica
- Transactions per second and active connections
- WAL archiving status and last backup age
- Volume usage

## Check that metrics and alerts arrived

```bash
kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 9090:9090
```

In http://localhost:9090:

- **Status → Targets**: `podMonitor/aswin-kl/task-4-7-aswin-pg/0` shows 3 targets UP,
  `podMonitor/aswin-kl/task-4-7-aswin-pg-poolers/0` shows 4 targets UP.
- **Alerts**: the `task-4-7-aswin-pg.*` groups are listed.
- Useful queries:

```promql
cnpg_collector_up{namespace="aswin-kl"}
cnpg_pg_replication_lag{namespace="aswin-kl"}
cnpg_pg_replication_streaming_replicas{namespace="aswin-kl"}
cnpg_backends_total{namespace="aswin-kl"}
cnpg_pgbouncer_pools_cl_active{namespace="aswin-kl"}
{__name__=~"barman_cloud.*", namespace="aswin-kl"}
```

If the last query returns nothing after a backup has completed, the plugin uses
different metric names in this version. Run
`{__name__=~".*backup.*", namespace="aswin-kl"}`, find the "last available
backup timestamp" metric, and update the three backup rules in
`prometheus-rules.yaml`.

## Fire an alert on purpose (demo)

`Task47PostgresInstanceDown` fires if an instance is missing for 2 minutes:

```bash
kubectl cnpg fencing on task-4-7-aswin-pg task-4-7-aswin-pg-3 -n aswin-kl
# wait ~2-3 minutes, show the alert as Pending, then Firing in Prometheus / Grafana
kubectl cnpg fencing off task-4-7-aswin-pg task-4-7-aswin-pg-3 -n aswin-kl
```

Pick a replica (check `kubectl cnpg status` first), never the primary.
