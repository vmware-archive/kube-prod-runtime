# BKPR components

## Elasticsearch

Elasticsearch is a distributed, RESTful search and analytics engine capable of solving a growing number of use cases. As the heart of the Elastic Stack, it centrally stores your data so you can discover the expected and uncover the unexpected.

### Implementation

BKPR uses Elasticsearch 5.6.12 as [packaged by Bitnami](https://hub.docker.com/r/bitnami/elasticsearch/). By default it runs 3 non-root pods named:

* `elasticsearch-logging-0`
* `elasticsearch-logging-1`
* `elasticsearch-logging-2`

all under the `kubeprod` namespace, forming an Elasticsearch cluster named `elasticsearch-cluster`.

There are two containers running inside each of these pods:

* `elasticsearch-logging`, which implements an Elasticsearch master node, and runs as UID `1001`.
* `prom-exporter`, a Prometheus exporter for various metrics about ElasticSearch.

In addition to these containers, there is also an special init container, `elasticsearch-logging-init`, which is required to reconfigure the `max_map_count` kernel, parameter for the entire pod and is stated by the [Elasticsearch documentation](https://www.elastic.co/guide/en/elasticsearch/reference/5.6/vm-max-map-count.html).

Finally, a headless Kubernetes Service named `elasticsearch-logging`, which is used to allow other components like Kibana or Fluentd access to the Elasticsearch cluster, but also used for discovery of Elasticsearch nodes in the cluster.

#### Networking

Elasticsearch Kubernetes Service uses default Elasticsearch ports:

* Port `9200/tcp`, used for end-user, HTTP-based access
* Port `9300/tcp`, used for internal communication between Elasticsearch nodes within the cluster

#### Storage

To assure persistence of the underlying Elasticsearch storage, each pod relies on a Kubernetes PersistentVolume named `data-elasticsearch-logging-%i` where `%i` is an index that matches the pod index. By default, each PersistentVolume is allocated 100Gi of storage.

### Overrides

While it is technically possible to override or change the behavior of any of Elasticsearch attributes, only the following overrides are supported:

#### Override pod replicas

```
$ cat kubeprod-manifest.jsonnet
# Cluster-specific configuration
(import "/Users/falfaro/go/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/aks+k8s-1.9.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    elasticsearch+: {
        replicas: 5,
        // min_master_nodes > round(replicas / 2)
        min_master_nodes: 3,
    }
}
```

## Kibana

[Kibana](https://www.elastic.co/products/kibana) lets you visualize your Elasticsearch data and navigate the Elastic Stack.

### Implementation

BKPR uses Kibana 5.6.12 as [packaged by Bitnami](https://hub.docker.com/r/bitnami/kibana/). By default it runs 1 non-root pod named `kibana` and also a Kubernetes Ingress resource named `kibana-logging` which allows end-user access to Kibana from the Internet. BKPR implements automatic DNS name registration for the `kibana-logging` Ingress resource based on the DNS suffix name specified when installing BKPR and also HTTP/S support (see cert-manager component for automatic management of X.509 certificates via Letsencrypt).

All these Kubernetes resources live under the `kubeprod` namespace.

#### Networking

Kibana exposes port `5601/tcp` internally to the Kubernetes cluster, but allows external access via HTTP/S by means of the deployed nginx-ingress-controller.
Kibana connects to the Elasticsearch cluster via the `elasticsearch-logging` Kubernetes Service defined in the Elasticsearch manifest.

#### Storage

Kibana is a stateless component and therefore does not have any persistent storage requirements.

## Prometheus

[Prometheus](https://prometheus.io/) is a popular open-source monitoring system and time series database written in Go. It features a multi-dimensional data model, a flexible query language, efficient time series database and modern alerting approach and integrates aspects all the way from client-side instrumentation to alerting.

### Implementation

BKPR uses Prometheus 2.3.2 as [packaged by Bitnami](https://hub.docker.com/r/bitnami/prometheus/). It is implemented as a [Kubernetes StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) with just 1 pod:

* `prometheus-0`

under the `kubeprod` namespace.

There are two containers running inside this pod:

* `prometheus`, which implements Prometheus, and runs as UID `1001`.
* `configmap-reload`, a sidecar container that will instruct Prometheus to reload its configuration it has been updated. See the section named Configuration reloading below.

### Configuration

Prometheus configuration is split across the two following files:

* `manifests/components/prometheus-config.jsonnet`, which describes the Kubernetes objects that are scraped (e.g. pods, ingresses, nodes, etc.)
* `manifests/components/prometheus.jsonnet`, which contains the set of monitoring rules and alerts.

This configuration is assembled into a Kubernetes ConfigMap and exposed inside the `prometheus` container as several YAML configuration files, like `basic.yaml`, `monitoring.yaml` and `prometheus.yanl`.

#### Configuration reloading

The `configmap-reload` container watches for updates to the Kubernetes ConfigMap that describes the Prometheus configuration. When this ConfigMap is updated, the `configmap-relaoder` will issue the following HTTP request to Prometheus, which cause a configuration reload: `http://localhost:9090/-/reload`.

#### Networking

Prometheus Kubernetes Service uses the default port:

* Port `9090/tcp`

#### Storage

To assure persistence of the timeseries database, among other things, each pod relies on a Kubernetes PersistentVolume named `data-prometheus-%i` where `%i` is an index that matches the pod index. By default, each PersistentVolume is allocated storage based on the following formula: `1.5 * retention_seconds * samples_per_second * bytes_per_sample / 1000000`, where:

* `retention_seconds` defaults to 183 days (in seconds)
* `samples_per_second` defaults to `166.66`
* `bytes_per_sample` defaults to `2`

Or about 8GiB of disk space. These parameter can be tweaked. Please read the Overrides section below.

### Overrides

While it is technically possible to override or change the behavior of any of Prometheus attributes, only the following overrides are supported:

#### Override storage parameters

The following example shows how to override the retention days, estimated number of timeseries, bytes per sample and overhead factor at the same time.

```
$ cat kubeprod-manifest.jsonnet
# Cluster-specific configuration
(import "/Users/falfaro/go/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/aks+k8s-1.9.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    prometheus+: {
        retention_days:: 366,
        time_series:: 10000,  // Wild guess
        bytes_per_sample:: 2,
        overhead_factor:: 1.5,
    }
}
```

#### Override for additional rules

The following example shows how to add a additional monitoring rules. The default configuration shipped with Prometheus brings in two different groups of rules, namely `basic.rules` and `monitoring.rules`, but you can create additional groups if you need to. Next we show how to add an additional monitoring rule:

```
$ cat kubeprod-manifest.jsonnet
# Cluster-specific configuration
(import "/Users/falfaro/go/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/aks+k8s-1.9.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    prometheus+: {
        monitoring_rules+: [
            {
                alert: "ElasticsearchDown",
                expr: "sum(elasticsearch_cluster_health_up) < 2",
                "for": "10m",
                labels: {severity: "critical"},
                annotations: {
                    summary: "Elastichsearch is unhealthy",
                    description: "Elasticsearch cluster quorum is not healthy",
                },
            },
        ]
    }
}
```
