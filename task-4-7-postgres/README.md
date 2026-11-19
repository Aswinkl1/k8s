# Task 4.7 — Production PostgreSQL on Kubernetes (CNPG)

A 3-instance PostgreSQL cluster managed by CloudNativePG, with PgBouncer
poolers for read/write split, continuous backups to Civo Object Storage,
Prometheus alerts and NetworkPolicies.

See [architecture.md](architecture.md) for the design and the answers to the
mandatory questions, and [07-demo/demo-script.md](07-demo/demo-script.md) for
the live demo.

## Naming

| Thing | Name |
|---|---|
| Namespace | `aswin-kl` |
| CNPG cluster | `task-4-7-aswin-pg` |
| Write endpoint (pooled) | `task-4-7-aswin-pooler-rw.aswin-kl.svc:5432` |
| Read endpoint (pooled) | `task-4-7-aswin-pooler-ro.aswin-kl.svc:5432` |
| App user / database | `app` / `app` |
| Object store | `task-4-7-aswin-objectstore` |

## Layout

```
00-prereqs/     what is already installed + how to create the Civo bucket
01-secrets/     script that creates the app-user and S3 secrets (no values in git)
02-cluster/     the CNPG Cluster
03-backup/      ObjectStore, ScheduledBackup, on-demand Backup, PITR restore example
04-pooler/      PgBouncer poolers (rw + ro)
05-network/     NetworkPolicies
06-monitoring/  PodMonitors, PrometheusRule, Grafana notes
07-demo/        client pods, pgbench job, demo script
```

## Install order

Run from the repository root. Check your context first:

```bash
kubectl config current-context
```

1. Prerequisites — CNPG operator, Barman Cloud plugin, cert-manager and the
   monitoring stack are already in the cluster. Verify with the commands in
   [00-prereqs/prereqs.md](00-prereqs/prereqs.md), and create the Civo bucket.

2. Secrets

   ```bash
   read -rs APP_DB_PASSWORD && export APP_DB_PASSWORD     # or: export APP_DB_PASSWORD=$(openssl rand -base64 24)
   read -rs S3_ACCESS_KEY_ID && export S3_ACCESS_KEY_ID
   read -rs S3_SECRET_ACCESS_KEY && export S3_SECRET_ACCESS_KEY
   ./01-secrets/create-secrets.sh
   ```

3. Object store (edit the bucket name and region first)

   ```bash
   kubectl apply -f 03-backup/objectstore.yaml
   ```

4. Cluster

   ```bash
   kubectl apply -f 02-cluster/cluster.yaml
   kubectl get cluster -n aswin-kl task-4-7-aswin-pg -w      # wait for "Cluster in healthy state"
   ```

5. Backups

   ```bash
   kubectl apply -f 03-backup/scheduled-backup.yaml
   kubectl get backups -n aswin-kl
   ```

6. Poolers

   ```bash
   kubectl apply -f 04-pooler/
   ```

7. NetworkPolicies

   ```bash
   kubectl apply -f 05-network/networkpolicy.yaml
   ```

8. Monitoring

   ```bash
   kubectl apply -f 06-monitoring/podmonitor.yaml
   kubectl apply -f 06-monitoring/prometheus-rules.yaml
   ```

9. Demo clients

   ```bash
   kubectl apply -f 07-demo/client-pod.yaml
   kubectl apply -f 07-demo/unauthorized-pod.yaml
   ```

## Quick health check

```bash
kubectl cnpg status task-4-7-aswin-pg -n aswin-kl
kubectl get cluster,pooler,backup,scheduledbackup -n aswin-kl
kubectl get pods -n aswin-kl -l cnpg.io/cluster=task-4-7-aswin-pg -L cnpg.io/instanceRole
```

## Teardown

```bash
kubectl delete -f 07-demo/ --ignore-not-found
kubectl delete -f 06-monitoring/ --ignore-not-found
kubectl delete -f 05-network/ -f 04-pooler/ --ignore-not-found
kubectl delete -f 03-backup/scheduled-backup.yaml -f 02-cluster/cluster.yaml --ignore-not-found
kubectl delete -f 03-backup/objectstore.yaml --ignore-not-found
kubectl delete secret -n aswin-kl task-4-7-aswin-app-user task-4-7-aswin-s3-creds --ignore-not-found
```

Deleting the Cluster deletes its PVCs. Backups in the bucket are kept.
