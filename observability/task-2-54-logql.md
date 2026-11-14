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
