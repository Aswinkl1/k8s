# Task 2.55 — Grafana Alerting

## 1. Contact Point

- **Name:** `task-2-55-contact-point-aswin-kl`
- **Type:** Webhook
- **Provider:** webhook.site
- **Purpose:** Receive alert notifications from Grafana.
- **Test:** Test notification sent to webhook.site.

## 2. CPU Alert Rule

| Setting             | Value                          |
| ------------------- | ------------------------------ |
| Name                | `task-2-55-cpu-alert-aswin-kl` |
| Data source         | Prometheus                     |
| Threshold           | CPU > 80%                      |
| Evaluation interval | 1 minute                       |
| Pending period      | 2 minutes                      |
| Keep firing for     | 0 seconds                      |
| Current state       | Normal                         |

### PromQL

```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

Calculates CPU usage percentage per node using the average idle CPU rate over 5 minutes.

### Labels

```yaml
severity: warning
team: platform
```

### Annotations

**Summary:**

```text
High CPU usage on {{ $labels.instance }}
```

**Description:**

```text
CPU usage on {{ $labels.instance }} has been above 80% for more than 2 minutes.
```

### Pending Period

The 2-minute pending period prevents alerts from firing during short CPU spikes, reducing unnecessary notifications.

## 3. Notification Routing

- **Routing:** Notification policy
- **Current policy:** Default policy
- **Current contact point:** `grafana-default-email`

Custom notification policy configuration is pending.

## 4. Pod Restart Alert Rule

| Setting             | Value                                  |
| ------------------- | -------------------------------------- |
| Name                | `task-2-55-pod-restart-alert-aswin-kl` |
| Data source         | Prometheus                             |
| Condition           | More than 3 restarts in 15 minutes     |
| Evaluation interval | 1 minute                               |
| Pending period      | 0 minutes                              |
| Severity            | critical                               |
| Team                | platform                               |
| No Data handling    | Normal                                 |

### PromQL

```promql
increase(kube_pod_container_status_restarts_total[15m]) > 3
```

Detects containers that restart more than 3 times within 15 minutes.

### Annotations

**Summary:**

```text
Pod {{ $labels.pod }} in {{ $labels.namespace }} is crash-looping
```

**Description:**

```text
Pod {{ $labels.pod }} has restarted {{ $values.A.Value }} times in the last 15 minutes
```

### Why no pending period?

Repeated container restarts indicate application instability. Unlike temporary CPU spikes, this condition requires immediate attention.

The alert fires as soon as the condition is detected.

## 6. Silence Configuration

- **Matchers:** `team=platform`,
- **Duration:** 1 hour
- **Purpose:** Suppress notifications during testing or planned maintenance.
- **Result:** Silence created successfully.

**Silence vs Resolved:**

- Silenced: Alert continues evaluating and may remain Firing, but notifications are suppressed.
- Resolved: The alert condition is no longer true.

**Production example:** Silence node alerts temporarily while performing planned Kubernetes node maintenance.
