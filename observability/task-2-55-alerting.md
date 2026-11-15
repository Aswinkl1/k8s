# Task 2.55 — Grafana Alerting

## 1. Contact Point

- **Name:** `task-2-55-contact-point-aswin-kl`

- **Type:** Webhook

- **Provider:** webhook.site

- **Purpose:** Receive Grafana alert notifications.

- **Test:** Test notification sent using Grafana.

## 2. CPU Alert Rule

| Setting             | Value                          |
| ------------------- | ------------------------------ |
| Name                | `task-2-55-cpu-alert-aswin-kl` |
| Data source         | Prometheus                     |
| Threshold           | CPU > 80%                      |
| Evaluation interval | 1 minute                       |
| Pending period      | 2 minutes                      |
| Severity            | warning                        |
| Team                | platform                       |
| Observed state      | Normal                         |

### PromQL

```
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

Calculates CPU usage percentage per instance using the average idle CPU rate over 5 minutes.

**Pending period:** The 2-minute delay prevents alerts from firing during brief CPU spikes.

**Annotations:**

- Summary: `High CPU usage on {{ $labels.instance }}`

- Description: `CPU usage on {{ $labels.instance }} has been above 80% for more than 2 minutes.`

**Verification:** PromQL returned valid CPU values. Alert state was Normal.

## 3. Pod Restart Alert Rule

| Setting             | Value                                  |
| ------------------- | -------------------------------------- |
| Name                | `task-2-55-pod-restart-alert-aswin-kl` |
| Data source         | Prometheus                             |
| Condition           | More than 3 restarts in 15 minutes     |
| Evaluation interval | 1 minute                               |
| Pending period      | 0 minutes                              |
| Severity            | critical                               |
| Team                | platform                               |
| Owner               | aswin-kl                               |
| No Data handling    | Normal                                 |
| Observed state      | Normal (No Data health)                |

### PromQL

```
increase(kube_pod_container_status_restarts_total[15m]) > 3
```

Detects containers that restarted more than 3 times during the last 15 minutes.

**Pending period:** Set to 0 because repeated restarts indicate application instability and require prompt attention.

**Annotations:**

- Summary: `Pod {{ $labels.pod }} in {{ $labels.namespace }} is crash-looping`

- Description: `Pod {{ $labels.pod }} has restarted {{ $values.A.Value }} times in the last 15 minutes`

**Verification:** Prometheus returned restart metrics. No containers matched the threshold in the observed results.

**No Data:** The query filters out containers with 3 or fewer restarts. Empty results are treated as Normal for this exercise. A separate alert should monitor missing metrics in production.

## 4. Notification Policy

**Routing tree:**

```
Default Policy → grafana-default-email
    |
    |-- severity=critical → Shared contact point
    |
    |-- severity=critical
            → task-2-55-contact-point-aswin-kl
```

**Custom policy configuration:**

| Setting         | Value                              |
| --------------- | ---------------------------------- |
| Matchers        | `severity=critical`                |
| Contact point   | `task-2-55-contact-point-aswin-kl` |
| Group by        | `namespace`, `pod`                 |
| Group wait      | 30 seconds                         |
| Group interval  | 5 minutes                          |
| Repeat interval | 1 hour                             |

- **Group by:** Combines alerts with matching grouping-label values.

- **Group wait:** Delays the first notification to collect related alerts.

- **Group interval:** Controls when changes to an existing group trigger another notification.

- **Repeat interval:** Sends reminders for unchanged, still-firing alerts.

**Example:** Ten different pods in the same namespace create ten groups when grouping by both `namespace` and `pod`. and 10 notification will be send .

## 5. Alert State Verification

### CPU Alert

- **State:** Normal

- **Health:** OK

- **Reason:** CPU usage was below the configured 80% threshold.

- **Verification:** The PromQL query was executed in Grafana Explore and returned valid CPU usage values.

### Pod Restart Alert

- **State:** Normal

- **Health:** No Data

- **Reason:** No containers matched the condition of more than 3 restarts in 15 minutes.

- **Verification:** The underlying restart metric was checked manually in Grafana Explore and showed restart increases of 0 for the observed containers.

**Note:** The pod restart rule uses `No Data → Normal`, so an empty query result is treated as Normal.

## 6. Silence

- **Matchers:** `team=platform`, `owner=aswin-kl`

- **Duration:** 1 hour

- **Comment:** Silencing platform team alerts for Task 2.55 testing

- **Purpose:** Suppress notifications during testing or planned maintenance.

**Silenced vs Resolved:**

- **Silenced:** Alert evaluation continues, but matching notifications are suppressed.

- **Resolved:** The alert condition is no longer true.

**Production example:** Silence alerts during planned Kubernetes node maintenance.

## 7. Inhibition Rule

```yaml
inhibit_rules:
  - source_matchers:
      - alertname="task-2-55-cpu-alert-aswin-kl"
      - severity="warning"
    target_matchers:
      - alertname="task-2-55-pod-restart-alert-aswin-kl"
      - severity="critical"
    equal:
      - instance
```

**Explanation:**

- **Source:** CPU alert that activates inhibition.

- **Target:** Pod restart alert whose notifications are suppressed.

- **Equal:** Both alerts must have the same `instance` label value.

**Purpose:** Reduce related notifications when high CPU usage and pod restarts occur together.

**Note:** This rule is documented but not deployed. Production implementation requires a common node-identifying label on both alerts. Suppressing a critical restart alert based on a warning-level CPU alert should also be reviewed carefully.

**Silence vs Inhibition:** A silence suppresses notifications for a specified time. Inhibition automatically suppresses related notifications while a matching source alert is firing.

**Node failure example:** If one node failure triggers 20 pod alerts, inhibition is preferable because it automatically suppresses related pod notifications.
