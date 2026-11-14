# part 1

the dashboard are stored in configmap and the graffana has sidecar container that watches these config maps and loads the dashboard .

```
kubectl get configmap -n aswin-kl -l grafana_dashboard=1
```

i ran the above command
the dashboard in graffana ui is organized in folders like

node explorer
k8s
k8s/ compute resources
k8s/networking
alert managers

# part 2 Node exporter full dashboard

## cpu usage

```
(

(1 - sum without (mode) (rate(node_cpu_seconds_total{job="node-exporter", mode=~"idle|iowait|steal", instance="$instance", cluster=~"$cluster"}[$__rate_interval])))

/ ignoring(cpu) group_left

count without (cpu, mode) (node_cpu_seconds_total{job="node-exporter", mode="idle", instance="$instance", cluster=~"$cluster"})

)
```

this measures the per core cpu time spent actively executing work . it excludes the mode idle , iowait , steal .

this node_cpu_seconds_total is a counter .

this help us to identify if the k8s node is having high cpu utilization .

## memory

this find how much ram is being used

```
(

node_memory_MemTotal_bytes{job="node-exporter", instance="$instance", cluster=~"$cluster"}

-

node_memory_MemFree_bytes{job="node-exporter", instance="$instance", cluster=~"$cluster"}

-

node_memory_Buffers_bytes{job="node-exporter", instance="$instance", cluster=~"$cluster"}

-

node_memory_Cached_bytes{job="node-exporter", instance="$instance", cluster=~"$cluster"}

)
```

This uses a gauge metrics .
to find the total memory uses . we need to subtract the memory uses for for kernal buffer and cache and free memory from the total memory

## disk

### disk output

```
rate(node_disk_read_bytes_total{job="node-exporter", instance="$instance", cluster=~"$cluster", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"}[$__rate_interval])
```

this metric is in counter and this show the total read bytes .

by taking the rage we get per sec value like mb/sec or kb/sec .

### disk input

```
rate(node_disk_written_bytes_total{job="node-exporter", instance="$instance", cluster=~"$cluster", device=~"(/dev/)?(mmcblk.p.+|nvme.+|rbd.+|sd.+|vd.+|xvd.+|dm-.+|md.+|dasd.+)"}[$__rate_interval])
```

this is a counter metrics . this show data writing

the metrics that powers the write throughput is node_disk_written_bytes_total

## network traffic

### incoming

```
rate(node_network_receive_bytes_total{job="node-exporter", instance="$instance", cluster=~"$cluster", device!="lo"}[$__rate_interval]) * 8
```

this is a counter that tracks the total number of bytes ,
the device-lo is used for local internal traffic . by filtering it out we get the network traffic

### transmitting

```
rate(node_network_transmit_bytes_total{job="node-exporter", instance="$instance", cluster=~"$cluster", device!="lo"}[$__rate_interval]) * 8
```

Calculates outgoing network throughput using rate() and converts bytes per second into bits per second by multiplying by 8.'

this also uses counter .

## load

```
node_load1{job="node-exporter", instance="$instance", cluster=~"$cluster"}
node_load5{job="node-exporter", instance="$instance", cluster=~"$cluster"}
node_load15{job="node-exporter", instance="$instance", cluster=~"$cluster"}
```

it uses a gauges metric

a system load is the average number of processes waiting for or using the cpu .
we calculate then over 1 , 5, 15 minutes .

## question

if we have 3 nodes and each node with 4 cpu core , lets say each core has 10 modes

we have 120 time series .

# part 3

Now we are looking inside of kubernetes / compute resource / cluster

## actual usage

```
cluster:node_cpu:ratio_rate5m{cluster="$cluster"}
```

this is a prometheus recording rule . it shows 52 per for now
this is the actual usage . this is how much all of the pod are taking from the cluster in terms of cpu

## request

```
sum(namespace_cpu:kube_pod_container_resource_requests:sum{cluster="$cluster"}) / sum(kube_node_status_allocatable{job="kube-state-metrics",resource="cpu",cluster="$cluster"})
```

it documents what percentage of cluster cpu is commited through pod cpu request .

this is calculated by total req cpu divided by the total allocatable cpu .

here it is 42.5 per

## limit

limit are the max cpu a container is allowed to use .
if it uses more than that the cpu get throttle .

```
sum(namespace_cpu:kube_pod_container_resource_limits:sum{cluster="$cluster"}) / sum(kube_node_status_allocatable{job="kube-state-metrics",resource="cpu",cluster="$cluster"})
```

it is calculated using the total limit / total allocatable cpu .
the allocatable cpu is the total cpu that is provieded .

## pod using less cpu that requested

on k8s / compute resource /namespace (pods) in the namespace monitoring i found that
the loki-stack-result-cache-0 . this pod is using less than what it is requested . it is only using 1.5 per of the requested cpu .

### cpu throttling

it means when a pod is using more cpu than its limit . the cpu will throttle . the pod becomes show .

```
rate(container_cpu_cfs_throttled_periods_total[5m])
/
rate(container_cpu_cfs_periods_total[5m])
```

this is how they find the throttle

## container label of pod

on k8s / compute resources / pod we can see that container level metric .

graffana know it because uses label . a container metics has label like contaienr name , namesapce , pod name . with that graffana know which metric are inside of it .

it uses a container label .

# part 4 k8s / networking

```
sum (

(8 * rate(container_network_receive_bytes_total{cluster="$cluster",namespace=~"$namespace"}[$__rate_interval]))

* on (cluster,namespace,pod) group_left ()

topk by (cluster,namespace,pod) (

1,

max by (cluster,namespace,pod) (kube_pod_info{host_network="false"})

)

)
```

the metrics is container_network_receive_bytes_total .
the metric type if counter .
the labels uses are cluster , namespace , pod ,

in production we can use this to see if a pod is experiencing high incoming traffic .

# part 5 Alert managet

## alerts

```
sum(alertmanager_alerts{namespace=~"$namespace",service=~"$service"}) by (namespace,service,instance)
```

alertmanager_alerts is a gauge metric .

it gets the no of alerts currently held by each selected alert manager instance .

Helps determine whether Alertmanager is receiving and retaining alerts while investigating monitoring or notification problems.

## alert receive rate

```
sum(rate(alertmanager_alerts_received_total{namespace=~"$namespace",service=~"$service"}[$__rate_interval])) by (namespace,service,instance)
```

this alertManaget_alerts_received_total is a counter .

it tracks the total no of alerts received by the alert manager .

Helps verify that Alertmanager is receiving alert updates from Prometheus and investigate unexpected changes in alert traffic.

# send rate

```
sum(rate(alertmanager_notifications_total{namespace=~"$namespace",service=~"$service", integration="$integration"}[$__rate_interval])) by (integration,namespace,service,instance)
```

`alertmanager_notifications_total` is a **Counter** that tracks the total number of notification attempts made by Alertmanager.

# notification latency

```
histogram_quantile(0.99,

sum(rate(alertmanager_notification_latency_seconds_bucket{namespace=~"$namespace",service=~"$service", integration="$integration"}[$__rate_interval])) by (le,namespace,service,instance)

)
```

It estimates the 99th percentile (P99) of Alertmanager notification latency, in seconds.

How long does Alertmanager take to send 99% of its notification attempts?
Helps investigate slow notification delivery and problems with notification integrations.
