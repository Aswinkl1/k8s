# stream selector

## All logs from the monitoring namespace:

```
{namespace="monitoring"}
```

this gives us all the logs from the monitoring namespace

![alt text](image-8.png)

## Logs from all Grafana pods specifically

```
{namespace="monitoring", pod=~"._grafana._"}
```

this filters namespace in the monitoring and then use regex for pod where if the pod label container graffana then it can get the logs .

![alt text](image-9.png)

# filter expression

## error from any pod

```
{namespace=~".+"} |= "error"
```

this gives us error logs from all of the namespace .

![alt text](image-10.png)

## error but not the 404

```
{namespace=~".+"} |= "error" != "404"
```

this give us error from all the namespace but exclude the 404 errors

![alt text](image-11.png)

# Metric query

## log line rate per sec grouped by namespace

```
sum by (namespace) (

rate({namespace=~".+"}[5m])

)
```

this get all the log from all the namsespace for the last 5 min . then get the per sec average log rate . add it and then group by namespace .

![alt text](image-12.png)

# parse fields

```
{namespace="monitoring"} | json | level=~"error|warn"
```

get the logs from the monitoring namespace and parse then into json . filter them with error or warn . but there are no logs right now .

![alt text](image-13.png)

# The difference between a stream selector and a filter expression

the diff is that a stream selector is used to select the stream and it uses labels to do it and its values are indexed . this is a must have value .

a filter expression is something that we uses to filter the logs bases on words or filter we use . this is an optional value

# Why Loki only indexes labels and not log content, and what trade-off this creates

loki only index the labels because indexing all of logs makes the index big and we need to store the index in someplace too . that become very expensive if out cluster is really big or we get a lot of logs

if we only index the label the index becomes very small and the cost is smaller too .

the tradeoff is that it might get slower for larger logs like if we have a stream group with a lot of logs getting and filter get a bit slower .

# Design Your Custom Dashboard

## Dashboard Focus: Namespace Resource Summary

I chose to build a **Namespace Resource Summary Dashboard** because I want to monitor the overall resource usage and health of a Kubernetes namespace.

The pre-built Grafana dashboards provide information about nodes and pods, but I want a single dashboard where I can see namespace-level resource consumption, identify pods consuming high resources, monitor restarts, and investigate errors.

## Panels

| Panel                        | Purpose                                                                                              |
| ---------------------------- | ---------------------------------------------------------------------------------------------------- |
| Total Running Pods           | Shows how many pods are currently running in the selected namespace.                                 |
| Pod Restart Count            | Helps identify pods whose containers are restarting frequently.                                      |
| CPU Usage by Pod             | Shows CPU consumption for individual pods to identify high CPU consumers.                            |
| Memory Usage by Pod          | Shows memory consumption for individual pods to identify high memory consumers.                      |
| Error Logs                   | Displays error logs from the selected namespace using Loki, helping troubleshoot application issues. |
| Total Namespace CPU Usage    | Shows the total CPU consumed by all pods in the selected namespace.                                  |
| Total Namespace Memory Usage | Shows the total memory consumed by all pods in the selected namespace.                               |

## Dashboard Variable

I will use **`$namespace`** as a dashboard variable.

This allows me to select different Kubernetes namespaces from a dropdown without creating separate dashboards for each namespace.

All seven panels will update based on the selected namespace.

## Goal

The main goal of this dashboard is to answer:

**"How much CPU and memory is this namespace consuming, which pods are consuming the most resources, and are there any pod restarts or errors that need investigation?"**

## custom dashboard

### panel 1 - total running pods

**Data source:** Prometheus
**Visualization:** Stat
**Unit:** Short
**Calculation:** Last (not null)

```
sum(kube_pod_status_phase{namespace="$namespace", phase="Running"} == 1)
```

this shows the no of pods that are currently running in the selected namespace

### Panel 2 — Pod Restarts — Last 1 Hour

**Data source:** Prometheus
**Visualization:** Time series
**Unit:** Short
**Legend:** `{{pod}}`

```
sum by (pod) (
  increase(
    kube_pod_container_status_restarts_total{namespace="$namespace"}[1h]
  )
)
```

Identifies pods whose containers have restarted over the previous hour. `increase()` estimates counter increases and may return fractional values.

### Panel 3 — CPU Usage by Pod

**Data source:** Prometheus
**Visualization:** Time series
**Unit:** Cores
**Legend:** `{{pod}}`

```
sum by (pod) (
  rate(
    container_cpu_usage_seconds_total{
      namespace="$namespace",
      container!="",
      container!="POD"
    }[5m]
  )
)
```

Shows CPU consumption in cores for each pod so I can identify high CPU consumers. `rate()` converts the CPU-time counter into CPU-seconds per second (cores).

### Panel 4 — Memory Usage by Pod

**Data source:** Prometheus
**Visualization:** Time series
**Unit:** Bytes (IEC)
**Legend:** `{{pod}}`

```
sum by (pod) (
  container_memory_working_set_bytes{
    namespace="$namespace",
    container!="",
    container!="POD"
  }
)
```

Shows the reported memory working set for each pod. This is a gauge, so it does not need `rate()`.

### Panel 5 — Namespace CPU Usage (% of Cluster Capacity)

**Data source:** Prometheus
**Visualization:** Gauge
**Unit:** Percent (0–100)
**Min / Max:** 0 / 100

```
100 *
sum(
  rate(container_cpu_usage_seconds_total{
    namespace="$namespace",
    container!="",
    container!="POD"
  }[5m])
)
/
sum(kube_node_status_capacity{resource="cpu", unit="core"})
```

Shows how much of the Kubernetes nodes' total CPU capacity is consumed by the selected namespace. This is **not** CPU usage as a percentage of pod requests or limits.

### Panel 7 — Namespace Error Logs

**Data source:** Loki
**Visualization:** Logs

```
{namespace="$namespace"} |~ "(?i)error"
```

Displays log lines containing `error`, regardless of capitalization, from the selected namespace, helping investigate problems alongside resource metrics.
