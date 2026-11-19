# Architecture — Production PostgreSQL on Kubernetes

**Namespace:** `aswin-kl`
**Cluster:** `kubenine-intern` (Civo, region `mum1`)

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
| Monitoring | Built-in exporters and two PodMonitors, scraped by the shared Prometheus in `monitoring`. Alerts are three Grafana rules on those metrics | Prometheus stores the series. Grafana raises the alerts (replication lag, disk, backup age). A chart can show a problem without paging anyone. |
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

## 3. How a read query is routed differently from a write

The login path is the same as a write: TLS, user `app`, the `pg-access: "true"` NetworkPolicy, then one of two PgBouncer pods. The difference is which Service PgBouncer opens the Postgres connection to.

| | Write | Read |
|---|---|---|
| App connects to | `task-4-7-aswin-pooler-rw` | `task-4-7-aswin-pooler-ro` |
| PgBouncer sends the query to | `task-4-7-aswin-pg-rw` | `task-4-7-aswin-pg-ro` |
| That Service selects | the one pod labelled primary | the pods labelled replica |
| What Postgres allows | reads and writes | reads only |

A read is spread across the two replicas. The replica is in recovery, so an `INSERT`, `UPDATE`, or `DELETE` sent to `ro` fails. The rows it returns can be a moment behind the primary, because the replica applies WAL after the primary has already committed.

The app uses `rw` for every write, and for a read that must see a change it just made (the order just placed, a balance just updated). It uses `ro` for lists, search, reports, and dashboards, where data a short time behind is fine. That keeps those queries off the primary.

CNPG also creates `task-4-7-aswin-pg-r`, which includes the primary and the replicas. This setup does not use it. Reads go only to replicas, writes only to the primary. An app that connects to `-r` (or straight to `-rw` or `-ro`, skipping PgBouncer) is dropped by the instance NetworkPolicy. Only the pooler pods are allowed to open port 5432 on the Postgres pods.

## 4. What happens step by step when the primary pod dies

Take the primary as `pg-1`, with `pg-2` and `pg-3` as replicas. Nothing in the app changes its hostname. `task-4-7-aswin-pooler-rw` stays the write address the whole time.

1. `pg-1` is gone. Open connections drop. A transaction that had not committed is rolled back. A transaction that had committed is already on disk on at least one replica, because a commit waits for that flush.
2. The operator sees the primary is not ready and starts a failover.
3. It asks `pg-2` and `pg-3` how much WAL each has received, on the instance manager port 8000, and promotes the one that is furthest ahead. That pod becomes the primary and starts a new timeline. Say that is `pg-2`.
4. The operator moves the primary label from `pg-1` to `pg-2`. The Service `task-4-7-aswin-pg-rw` keeps the same name and now selects `pg-2`. No DNS change.
5. PgBouncer's connections to the old primary fail. It opens new ones through `-rw`, which now land on `pg-2`. For a few seconds the app gets errors. It retries the failed transaction, and writes work again.
6. `pg-3` disconnects from the dead primary and starts streaming from `pg-2`. Until `pg-1` is back, `ro` has one replica.
7. The operator starts `pg-1` again on its existing volume. The instance manager runs `pg_rewind` so `pg-1` throws away anything it had that `pg-2` does not, then `pg-1` joins as a replica. The cluster is back to one primary and two replicas.

A deleted pod fails over in a few seconds. If the node itself is dead, Kubernetes first has to mark the pod not ready, so the same steps take longer, on the order of a minute. Anti-affinity is `preferred` because there are only three nodes: the replacement can share a node while one node is down. `required` would leave that pod Pending until the node returned.

## 5. Where backups go and how you would restore from one

Backups leave the cluster. They go to `s3://task-4-7-aswin-kl-pg-backups/` on `https://s3.ap-south-1.amazonaws.com`. The keys are in the secret `task-4-7-aswin-s3-creds`, referenced by `task-4-7-aswin-objectstore`. Under that bucket, Barman writes a folder for this cluster:

```
s3://task-4-7-aswin-kl-pg-backups/task-4-7-aswin-pg/
  base/    one folder per full copy of the data directory
  wals/    every WAL segment after the first backup, gzip
```

Two things are stored, and a restore needs both.

- **WAL, all the time.** The Barman sidecar on the primary uploads each finished WAL segment. `archive_timeout` is 300 seconds, so a segment is pushed at least every 5 minutes. WAL is the list of changes. On its own it cannot rebuild the database.
- **A base backup, once a day.** `task-4-7-aswin-daily-backup` runs at 02:00 UTC and takes the copy from a replica (`target: prefer-standby`), so the primary keeps serving writes. The first backup ran as soon as the schedule was applied. Retention is 7 days: older base backups, and the WAL only those backups needed, are deleted. A base backup on its own can only restore to 02:00 that day.

An extra base backup, for example just before a risky change, is `03-backup/backup-now.yaml`.

Failover does not help if someone runs a bad `DELETE` or a bad migration. Both replicas get that change too. The backup is what brings the data back.

### Restore

A restore does not rewind the live cluster. It creates a new cluster, `task-4-7-aswin-pg-restore`, from the backups. The original cluster keeps running.

Three things are set on that new cluster:

1. It is a new cluster, with one instance.
2. The recovery target time is a UTC timestamp from just before the bad change. That is the second Postgres must reach and then stop.
3. The backup location is the same bucket the live cluster writes to, folder `task-4-7-aswin-pg`. The new cluster reads that folder. It does not write into it.

Postgres then starts in recovery. It loads the newest base backup from before that time, replays WAL until the target time, and leaves out anything after it. It then leaves recovery and becomes a normal primary.

The restored cluster does not archive WAL, so it cannot write into the original cluster's folder in the bucket. The damaged rows can be copied back to the live primary, or the app can be pointed at the restored cluster.

## 6. What is monitored and what triggers an alert

Grafana watches the metrics Prometheus already stores. It raises an alert only for the three rules below. A chart can show a problem without paging you. Slack gets a message only after one of those rules has stayed true for its pending period.

Prometheus in the `monitoring` namespace scrapes two PodMonitors every 30 seconds. The Postgres pods expose port 9187, which is where replication lag comes from. The pooler pods expose port 9127. Disk usage is a kubelet metric for the three data volumes, not a number the database pods publish. The CNPG dashboard in Grafana reads those same series.

| Grafana rule                        | Fires when                                                                                                       | Pending period                             | Severity |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | -------- |
| `task-4-7-postgres-replication-lag` | `cnpg_pg_replication_lag` for a pod `task-4-7-aswin-pg-*` stays above 30 seconds                                 | 2 minutes, checked every 1 minute          | warning  |
| `task-4-7-postgres-disk-filling`    | Free bytes divided by capacity bytes on PVC `task-4-7-aswin-pg-1`, `-2`, or `-3` stays below 0.20                | 10 minutes, on the slower evaluation group | warning  |
| `task-4-7-postgres-backup-too-old`  | Time since `barman_cloud_cloudnative_pg_io_last_available_backup_timestamp` stays above 93600 seconds (26 hours) | 10 minutes, on the slower evaluation group | critical |

The first check that sees a breach marks the rule Pending. Slack is sent on a later check, once the pending period has elapsed, through the notification policy that matches `owner=aswin-kl` and sends to your Slack contact point. Replication lag is the one that can page within a few minutes. Disk and backup sit on the 10-minute group, so the first message for those arrives on the check after the pending period, not on the first check.

## 7. Who can connect

Two checks decide this, and a connection has to pass both. The NetworkPolicy decides who can open a TCP connection. `pg_hba` decides who Postgres will log in. Having the password is not enough on its own.

The application does not connect to a Postgres pod. It connects to a pooler on port 5432. The pooler NetworkPolicy allows that port only from pods in `aswin-kl` labelled `pg-access: "true"`. A pod in the same namespace without that label is dropped before PgBouncer sees it. Prometheus in `monitoring` is the other caller, and only on the metrics port 9127.

PgBouncer then opens its own connection to Postgres. The instance NetworkPolicy allows port 5432 only from the two poolers (`task-4-7-aswin-pooler-rw` and `task-4-7-aswin-pooler-ro`) and from the other Postgres pods in this cluster, which use it for replication. An application pod that tries the Postgres Service directly is dropped here.

Postgres then checks the login. `pg_hba` accepts only user `app`, database `app`, over TLS, with a SCRAM password. Every other network login is rejected. There is no `postgres` password. Admin work uses `kubectl cnpg psql` on the local socket, which does not go through this network rule.

The other openings on the Postgres pods are not for the application:

| Who | Port | Why |
|---|---|---|
| Other pods in `task-4-7-aswin-pg` | 5432 and 8000 | Replication and instance status |
| The operator in `cnpg-system` | 8000 | Status, promote, and fencing |
| Prometheus in `monitoring` | 9187 | The metrics exporter |

Anything not listed above cannot open a connection to the poolers or the Postgres pods.
