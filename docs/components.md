# BKPR components

## Elasticsearch

[Elasticsearch](https://elastic.co/products/elasticsearch) is a distributed, RESTful search and analytics engine capable of solving a growing number of use cases. As the heart of the Elastic Stack, it centrally stores your data so you can discover the expected and uncover the unexpected.

BKPR uses Fluentd to collect container logs from all containers from all namespaces, and also system logs from the underlying Kubernetes infrastructure (read the FLuentd section for a more detailed explanantion of which system logs are ingested). This data is stored in Elasticsearch and can be queried using Kibana.

### Implementation

BKPR uses Elasticsearch as [packaged by Bitnami](https://hub.docker.com/r/bitnami/elasticsearch/). By default it runs 3 non-root pods under the `kubeprod` namespace forming an Elasticsearch cluster named `elasticsearch-cluster`. It is implemented in the file `manifests/components/elasticsearch.jsonnet`. This manifest defines what an Elasticsearch pod and its nested containers look like:

* An Elasticsearch node
* A Prometheus exporter for collecting various metrics about Elasticsearch

Inside the manifest there is also a Kubernetes Service declaration used to allow other components (Kibana and Fluentd) access to the Elasticsearch cluster, and also used by Elasticsearch itself to perform node discovery in the cluster.

#### Networking

Elasticsearch Kubernetes Service uses default Elasticsearch ports:

* Port `9200/tcp`, used for end-user, HTTP-based access
* Port `9300/tcp`, used for internal communication between Elasticsearch nodes within the cluster

#### Storage

To assure durability of the underlying Elasticsearch storage, each pod relies on a Kubernetes PersistentVolume named `data-elasticsearch-logging-%i` where `%i` is an index that matches the pod index. By default, each PersistentVolume is allocated 100Gi of storage.

### Overrides

The following deployment parameters are supported, tested, and will be honoured across upgrades. Any other detail of the configuration may also be overridden, but may change on subsequent releases.

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

Kibana is externally accessible at `https://kibana.${dns-zone}` where `${dns-zone}` is the literal for the DNS zone specified when BKPR was installed.

### Implementation

BKPR uses Kibana as [packaged by Bitnami](https://hub.docker.com/r/bitnami/kibana/). By default it runs 1 non-root pod named `kibana` and also a Kubernetes Ingress resource named `kibana-logging` which allows end-user access to Kibana from the Internet. BKPR implements automatic DNS name registration for the `kibana-logging` Ingress resource based on the DNS suffix name specified when installing BKPR and also HTTP/S support (see cert-manager component for automatic management of X.509 certificates via Letsencrypt).

All these Kubernetes resources live under the `kubeprod` namespace.

#### Networking

Kibana exposes port `5601/tcp` internally to the Kubernetes cluster, but allows external access via HTTP/S by means of the deployed nginx-ingress-controller.
Kibana connects to the Elasticsearch cluster via the `elasticsearch-logging` Kubernetes Service defined in the Elasticsearch manifest.

#### Storage

Kibana is a stateless component and therefore does not have any persistent storage requirements.

## Prometheus

[Prometheus](https://prometheus.io/) is a popular open-source monitoring system and time series database written in Go. It features a multi-dimensional data model, a flexible query language, efficient time series database and modern alerting approach and integrates aspects all the way from client-side instrumentation to alerting.

### Implementation

BKPR uses Prometheus as [packaged by Bitnami](https://hub.docker.com/r/bitnami/prometheus/). It is implemented as a [Kubernetes StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) with just 1 pod named `prometheus-0` under the `kubeprod` namespace.

Prometheus scrapes several elements for relevant data which is stored as metrics in timeseries and can be queried using [Prometheus query language](https://prometheus.io/docs/prometheus/latest/querying/basics/) from the Prometheus console.  The prometheus console is externally accessible at `https://prometheus.${dns-zone}`, where `${dns-zone}` is the literal for the DNS zone specified when BKPR was installed.

#### Scraping

Among the elements scraped by our default Prometheus configuration:

* API servers
* Nodes
* Ingress and Service resources, which are probed using Prometheus Blackbox exporter
* Pods

#### Kubernetes Annotations

The following Kubernetes annotations on pods allow a fine control of the scraping process:

* `prometheus.io/scrape`: `true` to include the pod in the scraping process
* `prometheus.io/path`: required if the metrics path is not `/metrics`
* `prometheus.io/port`: required if the pod must be scraped on the indicated port instead of the pod’s declared ports

Adding these annotations to your own pods will cause Prometheus to also collect metrics from your service.

#### Synthetic Labels

Our default configuration adds two synthetic labels to help with querying data:

* `kubernetes_namespace` is the Kubernetes namespace of the pod the metric comes from. This label can be used to distinguish between the same component running in two separate namespaces.
* `kubernetes_pod_name` is the name of the pod the metric comes from. This label can be used to distinguish between metrics from different pods of the same Deployment or DaemonSet.

### Configuration

Prometheus configuration is split across the two following files:

* `manifests/components/prometheus-config.jsonnet`, which describes the Kubernetes objects that are scraped (e.g. pods, ingresses, nodes, etc.)
* `manifests/components/prometheus.jsonnet`, which contains the set of monitoring rules and alerts.

This configuration is assembled into a Kubernetes ConfigMap and injected into the Prometheus container as several YAML configuration files, named `basic.yaml`, `monitoring.yaml` and `prometheus.yanl`.

#### Configuration reloading

Inside a Prometheus pod there is a container named `configmap-reload` that watches for updates to the Kubernetes ConfigMap that describes the Prometheus configuration. When this Kubernetes ConfigMap is updated, `configmap-reloader` will issue the following HTTP request to Prometheus, which cause a configuration reload: `http://localhost:9090/-/reload`.

#### Networking

Prometheus Kubernetes Service uses the default port:

* Port `9090/tcp`

#### Storage

To assure persistence of the timeseries database, each pod relies on a Kubernetes PersistentVolume named `data-prometheus-%i` where `%i` is an index that matches the pod index. By default, each PersistentVolume is allocated a default storage of 6 months or 8GiB. In the Overrides section below there are instructions for reconfiguring this.

### Overrides

The following deployment parameters are supported, tested, and will be honoured across upgrades. Any other detail of the configuration may also be overridden, but may change on subsequent releases.

#### Override storage parameters

The following example shows how to override the retention days and storage volume size.

```
$ cat kubeprod-manifest.jsonnet
# Cluster-specific configuration
(import "/Users/falfaro/go/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/aks+k8s-1.9.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    prometheus+: {
        retention_days:: 366,
        storage:: 16384,  // (in Mi)
    }
}
```

#### Override for additional rules

The following example shows how to add additional monitoring rules. The default configuration shipped with Prometheus brings in two different groups of rules, namely `basic.rules` and `monitoring.rules`, but you can create additional groups if you need to. Next we show how to add an additional monitoring rule:

```
$ cat kubeprod-manifest.jsonnet
# Cluster-specific configuration
(import "/Users/falfaro/go/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/aks+k8s-1.9.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    prometheus+: {
        monitoring_rules+: {
            ElasticsearchDown: {
                expr: "sum(elasticsearch_cluster_health_up) < 2",
                "for": "10m",
                labels: {severity: "critical"},
                annotations: {
                    summary: "Elastichsearch is unhealthy",
                    description: "Elasticsearch cluster quorum is not healthy",
                },
            },
        },
    }
}
```
