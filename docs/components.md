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
(import "../../manifests/platforms/aks.jsonnet") {
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
(import "../../manifests/platforms/aks.jsonnet") {
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
(import "../../manifests/platforms/aks.jsonnet") {
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

## Fluentd

[Fluentd](https://www.fluentd.org/) is an open source data collector for unified logging layer. Fluentd allows you to unify data collection and consumption for a better use and understanding of data.

### Implementation

BKPR uses Fluentd as [packaged by Bitnami](https://hub.docker.com/r/bitnami/fluentd/). It is implemented as a [Kubernetes DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) named `fluentd-es` under the `kubeprod` namespace. This maps to one Fluentd pod per Kubelet.

### Usage

To have your logs collected by Fluentd and injected into Elasticsearch automatically, just must have the processes running inside the containers write to standard output and standard error streams in one of the log formats recognized by [Fluentd built-in parsers](https://docs.fluentd.org/v1.0/articles/parser-plugin-overview). Fluentd allows for [writing custom parsers](https://docs.fluentd.org/v1.0/articles/api-plugin-parser) when the built-in ones are not sufficient.

### Configuration

Fluentd configuration is split across several configuration files which have been downloaded from [upstream](https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/fluentd-elasticsearch/fluentd-es-configmap.yaml) by the `manifests/fluentd-es-config/import-from-upstream.py` tool. These configuration files are assembled into a Kubernetes ConfigMap and injected into the Fluentd container.

#### Configuration reloading

Fluentd supports reloading configuration file by gracefully restarting the worker process when it receives the SIGHUP signal. However, BKPR does not currently implement a mechanism to deliver a SIGHUP signal to Fluentd when any of the configuration files (assembled into a Kubernetes ConfigMap) are changed.

#### Networking

Fluentd sends its log stream to the Elasticsearch cluster over TCP. Elasticsearch networking requirements are described in the corresponding Elasticsearch section.

#### Storage

Fluentd uses the [Elasticsearch Output Plugin](https://docs.fluentd.org/v1.0/articles/out_elasticsearch/) to process system and Docker daemon logs and streams them into Elasticsearch. System logs are collected from the Kubelet's `/var/log` directory (via HostPath). Docker daemon logs are not collected from the Docker deamons but from the Kubelet's `/var/lib/docker/containers` (via HostPath). Fluentd requires a small amount of local storage on the host machine under `/var/log/fluentd-pos/` in the form of *pos* files to record the position it last read into each log file.

### Overrides

The following deployment parameters are supported, tested, and will be honoured across upgrades. Any other detail of the configuration may also be overridden, but may change on subsequent releases.

#### Resource requirements

To override pod memory or CPU:

```
$ cat kubeprod-manifest.jsonnet
# Cluster-specific configuration
(import "../../manifests/platforms/aks.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    fluentd_es+: {
        daemonset+: {
            spec+: {
                template+: {
                    spec+: {
                        containers_+: {
                            fluentd_es+: {
                                resources: {
                                    limits: {
                                        memory: "600Mi"
                                    },
                                    requests: {
                                        cpu: "200m",
                                        memory: "300Mi",
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
}
```

## NGINX Ingress Controller

[nginx-ingress](https://github.com/kubernetes/ingress-nginx) is an open source Kubernetes Ingress controller based on [NGINX](https://www.nginx.com).

An Ingress is a Kubernetes resource that lets you configure an HTTP load balancer for your Kubernetes services. Such a load balancer usually exposes your services to clients outside of your Kubernetes cluster. An Ingress resource supports exposing services and configuring TLS termination for each exposed host name.

### Implementation

It runs on top of Kubernetes and is implemented as a Kubernetes Deployment resource named `nginx-ingress-controller` inside the `kubeprod` namespace. A [HorizontalPodAutoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) resource is associated with this Deployment in order to auto-scale the number of `nginx-ingress-controller` pod replicas based on the incoming load.

It also relies on `ExternalDNS` to handle registration of Kubernetes Ingress resources in the DNS zone specified when BKPR was installed and `cert-manager` to request X.509 certificates for Kubernetes Ingress resources in order to provide transparent TLS termination.

The [`manifests/components/nginx-ingress.jsonnet`](../manifests/components/nginx-ingress.jsonnet)  manifest defines two Kubernetes Services:

* `nginx-ingress-controller`, which wraps the NGINX server running as a reverse proxy and the logic to derive its configuration and routing rules from Kubernetes Ingress and Service resources.
* `default-http-backend`, which is configured to respond to `/healthz` requests (liveness/readiness probes) and to return `404 Not Found` for any URL that does not match any of the known routing rules.

`nginx-ingress-controller` is configured to forward any URL that does not match any of the known routing rules to the `default-http-backend` Service.

### Configuration

No explicit configuration is required by the NGINX Ingress Controller.

#### Networking

The following ports are exposed:

* The `nginx-ingress-controller` Service exposes ports:
  * `80/tcp` and `443/tcp` to service HTTP and HTTP/S requests
  * `10254/tcp` for `/healthz` (liveness/readiness probes) and `/metrics` (Prometheus) endpoints.
* The `default-http-backend` Service exposes port `80/tcp` to render a `404 Not Found` error page for URLs that do not match any routing rule.

#### Monitoring

NGINX Ingress Controller currently exposes a `/metrics` endpoint for exposing metrics to Prometheus. Some of the metrics exported are:

* `connections_total`
* `requests_total`
* `read_bytes_total`
* `write_bytes_total`
* `request_duration_seconds` (histogram)
* `response_duration_seconds` (histogram)
* `request_size` (histogram)
* `response_size` (histogram)

For additional information, read the [source code](https://github.com/kubernetes/ingress-nginx/search?q=prometheus.Collector&unscoped_q=prometheus.Collector).

#### Storage

NGINX Ingress Controller is a stateless component and therefore does not have any persistent storage requirements.

### Overrides

The following deployment parameters are supported, tested, and will be honoured across upgrades. Any other details of the configuration may also be overridden, but may change on subsequent releases.

#### Override maximum number of replicas

The following example shows how to override the maximum number of replicas for NGINX Ingress Controller:

```
$ cat kubeprod-manifest.jsonnet
# Cluster-specific configuration
(import "../../manifests/platforms/aks.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    nginx_ingress+: {
        hpa+: {
            spec+: {
                maxReplicas: 10
            },
        },
    },
}
```

## cert-manager

[cert-manager](https://cert-manager.readthedocs.io/en/latest/) is a Kubernetes add-on to automate the management and issuance of TLS certificates. It will ensure certificates are valid and up to date periodically, and attempt to renew certificates at an appropriate time before expiry.

### Implementation

The [`ingress-shim`](https://github.com/jetstack/cert-manager/blob/master/docs/reference/ingress-shim.rst) component of `cert-manager` watches for Kubernetes Ingress resources across the cluster. If it observes an Ingress resource annotated with `kubernetes.io/tls-acme: true`, it will ensure a Certificate resource exists with the same name as the Ingress. A Certificate is a namespaced Kubernetes resource that references an Issuer or ClusterIssuer for information on how to obtain the certificate and current `spec` (`commonName`, `dnsNames`, etc.) and status (like last renewal time). `cert-manager` in BKPR is configured to use [Let's Encrypt](https://letsencrypt.org/) as the Certificate Authority for TLS certificates.

 Example:

```
$ kubectl --namespace=kubeprod get certificates
NAME                 AGE
kibana-logging-tls   20d
prometheus-tls       20d
```

and

```
$ kubectl --namespace=kubeprod describe certificates kibana-logging-tls
Name:         kibana-logging-tls
Namespace:    kubeprod
Labels:       <none>
Annotations:  <none>
API Version:  certmanager.k8s.io/v1alpha1
Kind:         Certificate
Metadata:
  Cluster Name:
  Creation Timestamp:  2018-10-01T10:47:44Z
  Generation:          0
  Owner References:
    API Version:           extensions/v1beta1
    Block Owner Deletion:  true
    Controller:            true
    Kind:                  Ingress
    Name:                  kibana-logging
    UID:                   5f439d5a-c567-11e8-b84a-0a58ac1f25fb
  Resource Version:        3557
  Self Link:               /apis/certmanager.k8s.io/v1alpha1/namespaces/kubeprod/certificates/kibana-logging-tls
  UID:                     6d529a2f-c567-11e8-b84a-0a58ac1f25fb
Spec:
  Acme:
    Config:
      Domains:
        kibana.${dns-zone}
      Http 01:
        Ingress:
        Ingress Class:  nginx
  Common Name:
  Dns Names:
    kibana.${dns-zone}
  Issuer Ref:
    Kind:       ClusterIssuer
    Name:       letsencrypt-prod
  Secret Name:  kibana-logging-tls
...
```

(`kibana.${dns-zone}` will use the actual DNS domain specified in the `--dns-zone` command-line argument to `kubeprod`).


#### Let's Encrypt Environments

Let's Encrypt suppports two environments:

* **Production**: meant for production deployments, enforces [rate-limits](https://letsencrypt.org/docs/rate-limits/) to prevent abuse so it is not suitable for testing or requesting multiple certificates for the same domain in a short period of time.
* **Staging**: for testing before using the production environment, has a [lower rate-limits](https://letsencrypt.org/docs/staging-environment/) than the production environment.

#### Networking

`cert-manager` exposes a Prometheus `/metrics` endpoint over port `9042/tcp`. `cert-manager` also requires Internet connectivity in order to communicate with Let's Encrypt servers.

#### Monitoring

`cert-manager` supports Prometheus by exporting a Prometheus `/metrics` endpoint over port `9402/tcp`. Please read the Prometheus section on Scraping and Kubernetes Annotations.

#### Storage

Certificates managed by `cert-manager` are stored as namespaced Kubernetes `Certificates` resources.

### Overrides

The following deployment parameters are supported, tested, and will be honoured across upgrades. Any other detail of the configuration may also be overridden, but may change on subsequent releases.

#### Override Let's Encrypt Environment

The following example shows how to request the use of Let's Encrypt staging environment:

```
$ cat kubeprod-manifest.jsonnet
# Cluster-specific configuration
(import "../../manifests/platforms/aks.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    cert_manager+: {
        letsencrypt_environment:: "staging",
    }
}
```
