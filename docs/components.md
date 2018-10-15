# BKPR components

## Elasticsearch

Elasticsearch is a distributed, RESTful search and analytics engine capable of solving a growing number of use cases. As the heart of the Elastic Stack, it centrally stores your data so you can discover the expected and uncover the unexpected.

### Implementation

BKPR uses Elasticsearch 5.6.12 as [packaged by Bitnami](https://hub.docker.com/r/bitnami/elasticsearch/). By default it runs 3 non-root pods named:

* `elasticsearch-logging-0`
* `elasticsearch-logging-1`
* `elasticsearch-logging-2`

all under the `kubeprod` namespace, forming an Elastic search cluster named `elasticsearch-cluster`.

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

While it is possible to override or change the behavior of technically any of Elasticsearch attributes, only the following overrides are supported:

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

BKPR uses Kibana 5.6.12 as [packaged by Bitnami](https://hub.docker.com/r/bitnami/kibana/). By default it runs 1 non-root pod named `kibana` and also a Kubernetes ingress resource named `kibana-logging` which allows end-user access to Kibana from the Internet. BKPR implements automatic DNS name registration for the `kibana-logging` ingress resource based on the DNS suffix name specified when installing BKPR and also HTTP/S support (see cert-manager component for automatic management of X.509 certificates via Letsencrypt).

All these Kubernetes resources live under the `kubeprod` namespace.

#### Networking

Kibana exposes port `5601/tcp` internally to the Kubernetes cluster, but allows access from the Internet via HTTP/S by means of a Kubernetes ingress controller.
Kibana connects to the Elasticsearch cluster via the `elasticsearch-logging` Kubernetes Service defined in the Elasticsearch manifest.

#### Storage

Kibana does not rely on any persistent storage.
