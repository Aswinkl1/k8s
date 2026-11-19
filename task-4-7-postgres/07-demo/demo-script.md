# Live demo script

Run these from the `task-4-7-postgres` directory. Every command uses `kubectl` and `-n aswin-kl`. There is no alias and no `kubectl cnpg` plugin.

`$RW_HOST` and `$RO_HOST` are environment variables inside the client pod, not in your terminal. The `bash -c '...'` quoting is what makes the pod expand them. If you write `psql -h "$RW_HOST"` without that inner shell, your terminal expands an empty variable and `psql` tries a local socket that does not exist.

## 0. Overview

```bash
kubectl get cluster -n aswin-kl task-4-7-aswin-pg
kubectl get pods -n aswin-kl -l cnpg.io/cluster=task-4-7-aswin-pg -o wide -L cnpg.io/instanceRole
kubectl get pooler,scheduledbackup,backup -n aswin-kl
kubectl get svc -n aswin-kl
```

What we saw: phase `Cluster in healthy state`, 3 instances, 3 ready, primary `task-4-7-aswin-pg-1`. Services `task-4-7-aswin-pg-rw`, `-ro`, `-r`, plus `task-4-7-aswin-pooler-rw` and `task-4-7-aswin-pooler-ro`.

The `NODE` column should show three different nodes. Anti-affinity is preferred, so confirm it rather than assuming it.

Client pods, if they are not already running:

```bash
kubectl apply -f 07-demo/client-pod.yaml -f 07-demo/unauthorized-pod.yaml
kubectl get pods -n aswin-kl -l app.kubernetes.io/part-of=task-4-7
```

## 1. Read/write split

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h $RW_HOST -qtAc "SELECT pg_is_in_recovery() AS replica, inet_server_addr() AS server"'

kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h $RO_HOST -qtAc "SELECT pg_is_in_recovery() AS replica, inet_server_addr() AS server"'
```

What we saw:

- Write path: `f|10.42.0.214`. `f` means primary.
- Read path: `t|10.42.1.65`. `t` means replica, and the IP was not the primary.

Repeating the read four times returned the same replica IP. That is PgBouncer reusing one server connection. It does not mean the second replica is missing. Show both replicas with:

```bash
kubectl get pods -n aswin-kl -l cnpg.io/cluster=task-4-7-aswin-pg -o wide -L cnpg.io/instanceRole
```

A write through the read pooler is rejected:

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h $RO_HOST -c "CREATE TABLE should_fail(id int)"'
```

Expected: `ERROR: cannot execute CREATE TABLE in a read-only transaction`.

## 2. Failover

Terminal 1, one insert per second through the write pooler:

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h $RW_HOST -c "CREATE TABLE IF NOT EXISTS heartbeat (id bigserial PRIMARY KEY, ts timestamptz DEFAULT now(), served_by inet DEFAULT inet_server_addr())"'

kubectl exec -it -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'while true; do
     psql -h $RW_HOST -qtAc "INSERT INTO heartbeat DEFAULT VALUES RETURNING id, ts, served_by" \
       || echo "$(date +%T) WRITE FAILED";
     sleep 1;
   done'
```

Terminal 2:

```bash
watch -n1 "kubectl get pods -n aswin-kl -l cnpg.io/cluster=task-4-7-aswin-pg -L cnpg.io/instanceRole"
```

Terminal 3, after a few successful inserts. `--grace-period=0 --force` kills the pod immediately so this is a crash, not a clean shutdown:

```bash
PRIMARY=$(kubectl get cluster task-4-7-aswin-pg -n aswin-kl -o jsonpath='{.status.currentPrimary}')
echo "Primary is $PRIMARY"
kubectl delete pod "$PRIMARY" -n aswin-kl --grace-period=0 --force
```

What we saw: writes failed for about 34 seconds (failed at second 37, resumed at second 71), then continued with a new `served_by` IP. A replica became `primary`, and the deleted pod came back as a replica. The failed inserts were never committed. The ones before the crash were on the synchronous replica.

Stop the loop with `Ctrl-C`, then:

```bash
kubectl get cluster -n aswin-kl task-4-7-aswin-pg
```

## 3. Connection pooling

`07-demo/pgbench-job.yaml` waits until the pooler accepts connections, then runs 500 clients for 120 seconds. The first run without that wait failed immediately with `connection refused`: the pooler NetworkPolicy had not yet allowed the brand-new pod. The client pod, which had been allowed for a long time, could connect the whole time. Delete a failed Job before applying again. A Job does not rerun on its own.

```bash
kubectl delete -f 07-demo/pgbench-job.yaml --ignore-not-found
kubectl apply -f 07-demo/pgbench-job.yaml
kubectl logs -n aswin-kl job/task-4-7-aswin-pgbench -f
```

Wait for `Running 500 clients for 120s`. In another terminal:

```bash
PRIMARY=$(kubectl get cluster task-4-7-aswin-pg -n aswin-kl -o jsonpath='{.status.currentPrimary}')
kubectl exec -n aswin-kl "$PRIMARY" -c postgres -- \
  psql -c "SELECT usename, state, count(*) FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY 1,2 ORDER BY 3 DESC;"
```

What we saw while the 500 clients were running:

| usename | state | count |
|---|---|---|
| app | active | 29 |
| app | idle in transaction | 10 |
| app | idle | 1 |
| cnpg_pooler_pgbouncer | idle | 9 |
| postgres | active | 1 |

The `app` rows add up to 40, which is two PgBouncer pods times a pool of 20. The `postgres` row is the session running this query.

Final pgbench line:

```text
number of clients: 500
duration: 120 s
number of transactions actually processed: 113755
number of failed transactions: 0 (0.000%)
latency average = 522.000 ms
tps = 955.379017 (without initial connection time)
```

The Job does not run again. Remove it when you have the numbers:

```bash
kubectl delete -f 07-demo/pgbench-job.yaml
```

## 4. Backup and point-in-time restore

Backups go to `s3://task-4-7-aswin-kl-pg-backups/` in `ap-south-1`. WAL segments are uploaded when they fill (16 MB). `archive_timeout` is `300`, so a quiet segment is also closed at least every 5 minutes.

```bash
kubectl get scheduledbackup,backup -n aswin-kl
```

Wait until a Backup phase is `completed` before deleting any rows.

Create the rows. The `$$` quoting is what worked from this shell. Single quotes let the pod expand `$RW_HOST`:

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h "$RW_HOST" -c "CREATE TABLE IF NOT EXISTS customers (id serial PRIMARY KEY, name text); INSERT INTO customers(name) SELECT \$\$customer-\$\$ || g FROM generate_series(1,100) g;"'

kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h "$RW_HOST" -qtAc "SELECT to_char(now() AT TIME ZONE \$\$UTC\$\$, \$\$YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"\$\$), count(*) FROM customers;"'
```

What we saw: `CREATE TABLE`, `INSERT 0 100`, then `2026-11-18T20:42:37Z|100`. Copy whatever timestamp you get. That value is the restore input for this accident, not a permanent setting.

Wait a few seconds, delete the rows, and close the WAL segment so S3 has it:

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h "$RW_HOST" -c "DELETE FROM customers;"'

PRIMARY=$(kubectl get cluster task-4-7-aswin-pg -n aswin-kl -o jsonpath='{.status.currentPrimary}')
kubectl exec -n aswin-kl "$PRIMARY" -c postgres -- psql -c "SELECT pg_switch_wal();"
```

The delete is replicated immediately. Killing the primary does not bring the rows back.

Put the copied timestamp into `recoveryTarget.targetTime` in `03-backup/restore-pitr.yaml`. The value we used was `2026-11-18T20:42:37Z`. The placeholder `2026-11-18T18:30:00Z` is before the rows existed, so a restore to it would not show them.

```bash
kubectl apply -f 03-backup/restore-pitr.yaml
kubectl get pods -n aswin-kl -l cnpg.io/cluster=task-4-7-aswin-pg-restore -w
```

What we saw: a `full-recovery` job went to `Completed` (the backup download and WAL replay finished). The database pod `task-4-7-aswin-pg-restore-1` then restarted on its own and came back `Running`. That restart is the operator leaving recovery mode and starting it as a normal primary.

Count on the restored pod. The client pod cannot reach it through the NetworkPolicy, so query inside the pod:

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-restore-1 -c postgres -- \
  psql -d app -c "SELECT count(*) FROM customers;"
```

What we saw: `100`.

The live database still had `0`. Copy the recovered rows back before deleting the restore cluster. `pg_dump` keeps the original ids. A `serial` does not rewind after `DELETE`, so new rows on the live cluster would have been 101 and up, and ids 1–100 were free.

```bash
PRIMARY=$(kubectl get cluster task-4-7-aswin-pg -n aswin-kl -o jsonpath='{.status.currentPrimary}')
kubectl exec -n aswin-kl task-4-7-aswin-pg-restore-1 -c postgres -- \
  pg_dump -d app -t customers --data-only \
| kubectl exec -i -n aswin-kl "$PRIMARY" -c postgres -- psql -d app

kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h "$RW_HOST" -c "SELECT count(*) FROM customers;"'
```

What we saw through the write pooler: `100`. Then remove the spare cluster:

```bash
kubectl delete -f 03-backup/restore-pitr.yaml
```

There is no automatic merge. The two clusters forked at the target time. Production copies the damaged table back, as above, and leaves later good writes in place. Replacing the live cluster with the restored one would throw those later writes away.

## 5. Monitoring

Grafana was not opened in this run. The rules were applied for the Prometheus in the `monitoring` namespace. Both PodMonitors and the PrometheusRule carry `release: prometheus-stack`. The NetworkPolicy allows that namespace onto port 9187 (database) and 9127 (pooler).

```bash
kubectl get prometheusrule -n aswin-kl task-4-7-aswin-pg-alerts --show-labels
kubectl get podmonitor -n aswin-kl
```

To see them loaded, port-forward the Prometheus service in `monitoring` (not the Grafana service) and open http://localhost:9090/rules. The group is `task-4-7-aswin-pg.availability`.

```bash
kubectl get svc -n monitoring | grep prometheus
kubectl port-forward -n monitoring svc/<prometheus-service-name> 9090:9090
```

## 6. Security

The intruder has the app password and no `pg-access` label. `PGCONNECT_TIMEOUT` is 5 seconds.

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-intruder -- bash -c 'psql -h "$RW_HOST" -c "SELECT 1"'
kubectl exec -n aswin-kl task-4-7-aswin-pg-intruder -- bash -c 'psql -h "$DB_HOST" -c "SELECT 1"'
```

Both should end with `timeout expired`. The second host is the database service, so the intruder cannot skip the pooler.

The allowed pod still connects:

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'psql -h "$RW_HOST" -c "SELECT current_user, inet_server_addr()"'
```

Expected: `app` and the primary IP.

A superuser login from the application is refused. What we saw was `FATAL: password authentication failed` from PgBouncer. There is no superuser password (`enableSuperuserAccess: false`), so the pooler stops it before a database session starts. That failure is the successful check.

```bash
kubectl exec -n aswin-kl task-4-7-aswin-pg-client -- bash -c \
  'PGPASSWORD=x psql -h "$RW_HOST" -U postgres -c "SELECT 1"'
```

The role itself has no extra attributes. An empty Attributes column means no Superuser, Create role, Create DB, or Replication:

```bash
PRIMARY=$(kubectl get cluster task-4-7-aswin-pg -n aswin-kl -o jsonpath='{.status.currentPrimary}')
kubectl exec -n aswin-kl "$PRIMARY" -c postgres -- psql -c "\du app"
```

Run the secret search from this directory. From a parent directory it also prints unrelated files.

```bash
grep -rniE "password:|secret_key|access_key" --include=*.yaml . | grep -v secretKeyRef
```

What we saw from this directory: `key: ACCESS_KEY_ID` and `key: ACCESS_SECRET_KEY` in `objectstore.yaml` (names of secret keys, not the values), and the word "password" in a comment in `unauthorized-pod.yaml`. No password value.

```bash
kubectl get networkpolicy -n aswin-kl
```

## Troubleshooting

| Symptom | What it was |
|---|---|
| `psql` looks for `/var/run/postgresql/.s.PGSQL.5432` | `$RW_HOST` was expanded on your machine, where it is empty. Use `bash -c 'psql -h "$RW_HOST" ...'`. |
| pgbench `connection refused` while the client pod works | The new Job pod connected before the NetworkPolicy allowed it. The wait loop in `pgbench-job.yaml` covers that. Delete the Job and apply it again. |
| Read IP never changes | PgBouncer is reusing one server connection. Check both replica IPs with `kubectl get pods -o wide`. |
| Restore pod goes `Running`, then `Completed`, then a new pod is `Pending` | The `full-recovery` job finished and the instance restarted out of recovery mode. Wait until it stays `Running`. |
| `grep` prints passwords from other projects | The command was not run in `task-4-7-postgres`. |
