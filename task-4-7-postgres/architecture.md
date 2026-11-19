# Architecture — Production PostgreSQL on Kubernetes

## 1. What you deployed and why you chose it over the alternatives

Namespace `aswin-kl` holds one CloudNativePG cluster, `task-4-7-aswin-pg`. The operator and the Barman Cloud plugin were already on the shared cluster in `cnpg-system` (operator 1.30.2, plugin v0.16.0). This task did not install a second operator.

| Piece | What is running | Why this shape |
|---|---|---|
| Postgres | 17.6, 3 instances, 5Gi `civo-volume` each | One primary and two replicas. A single pod has no failover and no second copy of the data. |
| Replication | Streaming, synchronous quorum: any 1 of the 2 replicas must flush each commit (`dataDurability: required`) | A commit is on disk on the primary and on at least one replica before it returns. If no replica is available, writes block instead of silently going asynchronous. |
| Placement | Pod anti-affinity `preferred` on `kubernetes.io/hostname` | The cluster has 3 nodes. Preferred spreads instances in normal operation. Required would leave a replacement pod Pending for the whole time a node is down. |
| App access | Role `app`, database `app`, superuser access off | The app owns one database. There is no `postgres` password. Admin work is `kubectl cnpg psql` over the local socket, which needs Kubernetes RBAC. |
| Pooling | Two CNPG `Pooler`s (PgBouncer, transaction mode), 2 pods each: `rw` to the primary, `ro` to the replicas | Postgres uses one process per connection. App pods plus autoscaling would exhaust `max_connections` (100). PgBouncer holds a real backend only for one transaction. |
| Backups | Barman Cloud plugin: continuous WAL archive plus a daily base backup at 02:00 UTC from a replica, 7-day retention | WAL alone cannot restore (it needs a starting copy). A base backup alone can only restore to 02:00. Together they support point-in-time recovery. The bucket is `s3://task-4-7-aswin-kl-pg-backups/` on `https://s3.ap-south-1.amazonaws.com`, outside the cluster. |
| Monitoring | Built-in exporters and two PodMonitors, scraped by the shared Prometheus in `monitoring`. Alerts are Grafana alerts on those metrics | Prometheus stores the series. Grafana raises the alerts (instance down, replication lag, disk, connections, backup age). No PrometheusRule. |
| Network | NetworkPolicies on the pooler and instance pods, plus `pg_hba` that accepts only `app` over TLS and then rejects | NetworkPolicy decides who can open a TCP connection. `pg_hba` decides who Postgres will log in. |

We chose CloudNativePG because the operator itself picks the new primary and moves the write Service, using the Kubernetes API, and PgBouncer pooling and Barman backups are part of that same operator instead of separate pieces that have to track failover on their own.

Backups use the Barman Cloud plugin (`ObjectStore` `task-4-7-aswin-objectstore`) rather than the older in-tree `spec.backup.barmanObjectStore`, which current CNPG deprecates. The plugin runs as a sidecar in each instance pod.

## 2. How a write query travels from application to database and back

A write never connects to a Postgres pod directly. It goes through the write pooler, and that pooler talks only to the current primary.

1. The app opens a TLS connection to `task-4-7-aswin-pooler-rw.aswin-kl.svc:5432` as user `app`, database `app`. The password comes from the `task-4-7-aswin-app-user` secret.
2. The pooler NetworkPolicy allows port 5432 only from pods in `aswin-kl` labelled `pg-access: "true"`. Any other pod is dropped here, before Postgres sees the query.
3. The Service sends the connection to one of the two PgBouncer pods. PgBouncer checks the password. It does not open a Postgres connection yet.
4. When the app starts a transaction, PgBouncer borrows one real connection from its pool (20 per pod) and sends it to `task-4-7-aswin-pg-rw`. That Service selects only the pod labelled primary, so both pooler pods always reach the same primary.
5. The instance NetworkPolicy allows that connection because it comes from a pooler pod. Postgres then accepts it only if it is TLS, user `app`, database `app`. Every other login is rejected by `pg_hba`.
6. The primary writes the change to its WAL and streams that WAL to both replicas. `COMMIT` does not return until at least one replica has flushed the WAL to disk.
7. The result travels back the same way: primary to PgBouncer to the app. PgBouncer puts the Postgres connection back in the pool for the next transaction.

The reply the app sees is the commit. Copying WAL to S3 happens after that, on the primary's Barman sidecar, and is not part of this round trip.
