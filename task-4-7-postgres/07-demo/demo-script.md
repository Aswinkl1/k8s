# Live demo script

All commands assume namespace `aswin-kl`. Set these once:

```bash
export NS=aswin-kl
export PG=task-4-7-aswin-pg
alias k=kubectl
```

Before starting, make sure the client pods are running:

```bash
k apply -f 07-demo/client-pod.yaml -f 07-demo/unauthorized-pod.yaml
k get pods -n $NS -l app.kubernetes.io/part-of=task-4-7
```

## 0. Overview (30 seconds)

```bash
k cnpg status $PG -n $NS
k get cluster,pooler,scheduledbackup,backup -n $NS
k get pods -n $NS -o wide -l cnpg.io/cluster=$PG -L cnpg.io/instanceRole
```

Point out: 3 instances on 3 different nodes, one primary, synchronous
replication, continuous archiving `OK`, poolers ready.

## 1. Read/write split

```bash
# Write endpoint -> primary (pg_is_in_recovery = f)
k exec -n $NS task-4-7-aswin-pg-client -- bash -c \
  'psql -h $RW_HOST -qtAc "SELECT pg_is_in_recovery() AS replica, inet_server_addr() AS server"'

# Read endpoint -> replica (pg_is_in_recovery = t). Run a few times: two different replica IPs.
for i in 1 2 3 4; do
  k exec -n $NS task-4-7-aswin-pg-client -- bash -c \
    'psql -h $RO_HOST -qtAc "SELECT pg_is_in_recovery() AS replica, inet_server_addr() AS server"'
done

# Match IPs to pods and roles
k get pods -n $NS -l cnpg.io/cluster=$PG -o wide -L cnpg.io/instanceRole

# A write on the read endpoint is refused
k exec -n $NS task-4-7-aswin-pg-client -- bash -c \
  'psql -h $RO_HOST -c "CREATE TABLE should_fail(id int)"'
# ERROR: cannot execute CREATE TABLE in a read-only transaction
```

## 2. Failover: kill the primary, writes resume

Terminal 1, heartbeat writer (one insert per second through the write pooler):

```bash
k exec -n $NS task-4-7-aswin-pg-client -- bash -c \
  'psql -h $RW_HOST -c "CREATE TABLE IF NOT EXISTS heartbeat (id bigserial PRIMARY KEY, ts timestamptz DEFAULT now(), served_by inet DEFAULT inet_server_addr())"'

k exec -it -n $NS task-4-7-aswin-pg-client -- bash -c \
  'while true; do
     psql -h $RW_HOST -qtAc "INSERT INTO heartbeat DEFAULT VALUES RETURNING id, ts, served_by" \
       || echo "$(date +%T) WRITE FAILED";
     sleep 1;
   done'
```

Terminal 2, watch the cluster:

```bash
watch -n1 "kubectl get pods -n $NS -l cnpg.io/cluster=$PG -L cnpg.io/instanceRole"
```

Terminal 3, kill the primary:

```bash
PRIMARY=$(k get cluster $PG -n $NS -o jsonpath='{.status.currentPrimary}')
echo "Primary is $PRIMARY"
k delete pod $PRIMARY -n $NS --grace-period=0 --force
```

What to show:

- Terminal 1: a few `WRITE FAILED` lines, then inserts continue with a **new** `served_by` IP.
- Terminal 2: a replica gets the `primary` role; the deleted pod comes back as a replica.
- Afterwards:

```bash
k cnpg status $PG -n $NS
k get cluster $PG -n $NS -o jsonpath='{.status.currentPrimary}{"\n"}'
# Measure the gap in the heartbeat
k cnpg psql $PG -n $NS -- app -c \
  "SELECT max(gap) AS longest_write_gap FROM (SELECT ts - lag(ts) OVER (ORDER BY id) AS gap FROM heartbeat) g;"
```

For a node failure instead of a pod failure (optional, ask before doing this on a shared cluster):
`kubectl drain <node-of-primary> --ignore-daemonsets --delete-emptydir-data`, then `kubectl uncordon` it.

## 3. Connection pooling under load

```bash
k apply -f 07-demo/pgbench-job.yaml
k logs -n $NS job/task-4-7-aswin-pgbench -f
```

While pgbench runs (500 clients), in another terminal:

```bash
# Backends actually open on the primary: ~40, not 500
k cnpg psql $PG -n $NS -- -c \
  "SELECT usename, state, count(*) FROM pg_stat_activity WHERE backend_type = 'client backend' GROUP BY 1,2 ORDER BY 3 DESC;"

# PgBouncer's view: client connections vs server connections
POOLER_POD=$(k get pods -n $NS -l cnpg.io/poolerName=task-4-7-aswin-pooler-rw -o jsonpath='{.items[0].metadata.name}')
k port-forward -n $NS pod/$POOLER_POD 9127:9127 &
curl -s localhost:9127/metrics | grep -E "^cnpg_pgbouncer_pools_(cl_active|cl_waiting|sv_active|sv_idle)"
kill %1
```

Show in Grafana as well: `cnpg_pgbouncer_pools_cl_active` (hundreds) vs
`cnpg_backends_total` (tens).

Clean up: `k delete -f 07-demo/pgbench-job.yaml`

## 4. Backups and point-in-time restore

Show that backups exist:

```bash
k get scheduledbackup,backup -n $NS
k describe backup -n $NS $(k get backup -n $NS -o jsonpath='{.items[-1].metadata.name}') | grep -E "Phase|Started|Stopped|Begin Wal|End Wal"
k cnpg status $PG -n $NS | grep -A4 -i "continuous backup"
# Bucket contents (Civo dashboard, or any S3 client), e.g.:
# aws --endpoint-url https://objectstore.<REGION>.civo.com s3 ls s3://<BUCKET>/task-4-7-aswin-pg/ --recursive | tail
```

Simulate the accident:

```bash
RW=task-4-7-aswin-pooler-rw.aswin-kl.svc

# 1. Some important data
k exec -n $NS task-4-7-aswin-pg-client -- psql -h $RW -c \
  "CREATE TABLE IF NOT EXISTS customers (id serial PRIMARY KEY, name text);
   INSERT INTO customers(name) SELECT 'customer-' || g FROM generate_series(1,100) g;"

# 2. Note the time just before the mistake (UTC). Copy the first column.
k exec -n $NS task-4-7-aswin-pg-client -- psql -h $RW -qtAc \
  "SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'), count(*) FROM customers;"

sleep 5

# 3. The mistake
k exec -n $NS task-4-7-aswin-pg-client -- psql -h $RW -c "DELETE FROM customers;"

# 4. Force the current WAL segment (containing the DELETE) to be archived now
k cnpg psql $PG -n $NS -- -c "SELECT pg_switch_wal();"
```

Note: failover cannot help here. The DELETE was replicated to both replicas
within milliseconds.

Restore:

```bash
# 5. Put the timestamp from step 2 into recoveryTarget.targetTime
vi 03-backup/restore-pitr.yaml
k apply -f 03-backup/restore-pitr.yaml
k get pods -n $NS -l cnpg.io/cluster=task-4-7-aswin-pg-restore -w
k cnpg status task-4-7-aswin-pg-restore -n $NS

# 6. The rows are back in the restored cluster
k cnpg psql task-4-7-aswin-pg-restore -n $NS -- app -c "SELECT count(*) FROM customers;"
```

Explain next steps: either copy the rows back into the live cluster
(`pg_dump -t customers` from the restored cluster, then restore into the
primary) or, for a full rollback, switch the poolers to the restored cluster.

Clean up: `k delete -f 03-backup/restore-pitr.yaml`

## 5. Monitoring

Follow [06-monitoring/grafana.md](../06-monitoring/grafana.md):

- Open the CNPG dashboard and show live replication lag, connections, TPS,
  archiving and backup age (run pgbench again for visible activity).
- Show the alert rules in Prometheus → Alerts.
- Trigger `Task47PostgresInstanceDown` by fencing a replica, show it firing,
  then unfence.

## 6. Security

Unauthorised pod is blocked (even with the correct password):

```bash
k exec -n $NS task-4-7-aswin-pg-intruder -- bash -c 'psql -h $RW_HOST -c "SELECT 1"'
# psql: error: connection to server ... timeout expired

k exec -n $NS task-4-7-aswin-pg-intruder -- bash -c 'psql -h $DB_HOST -c "SELECT 1"'
# timeout expired (cannot bypass the pooler and reach Postgres directly either)
```

Authorised pod works:

```bash
k exec -n $NS task-4-7-aswin-pg-client -- bash -c 'psql -h $RW_HOST -c "SELECT current_user, inet_server_addr()"'
```

No superuser for the application:

```bash
# No superuser secret was generated
k get secrets -n $NS | grep $PG

# The app role has no superuser / createrole / createdb / replication attributes
k cnpg psql $PG -n $NS -- -c "\du app"

# Superuser login over the network is rejected by pg_hba
k exec -n $NS task-4-7-aswin-pg-client -- bash -c 'PGPASSWORD=x psql -h $RW_HOST -U postgres -c "SELECT 1"'
```

Credentials are not in any manifest:

```bash
grep -rniE "password:|secret_key|access_key" --include=*.yaml . | grep -v secretKeyRef
```

Show the policies:

```bash
k get networkpolicy -n $NS
k describe networkpolicy -n $NS task-4-7-aswin-pg-poolers
```

## Troubleshooting during the demo

| Symptom | Check |
|---|---|
| Pod rejected on create | `k get events -n $NS --sort-by=.lastTimestamp` — Kyverno message names the missing label or securityContext field |
| Cluster stuck in "Setting up primary" | `k logs -n $NS -l cnpg.io/cluster=$PG --all-containers --tail=50`, check the PVC is Bound |
| Archiving not OK in `cnpg status` | `k logs -n $NS <pod> -c plugin-barman-cloud`, check bucket name, region, keys |
| Intruder pod is NOT blocked | NetworkPolicy not enforced; `k get networkpolicy -n $NS`, confirm k3s network policy controller is enabled |
| Authorised pod is blocked too | Pod is missing the `pg-access: "true"` label |
| Writes hang instead of failing | Both replicas down while `dataDurability: required` — this is intentional, bring a replica back |
