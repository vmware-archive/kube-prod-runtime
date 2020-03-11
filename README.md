# Bitnami Kubernetes Production Runtime

## Description

The Bitnami Kubernetes Production Runtime (BKPR) is a collection of services that makes it easy to run production workloads in Kubernetes.

Think of Bitnami Kubernetes Production Runtime as a curated collection of the services you would need to deploy on top of your Kubernetes cluster to enable logging, monitoring, certificate management, automatic discovery of Kubernetes resources via public DNS servers and other common infrastructure needs.

![BKPR](images/BKPR.png)

BKPR is available for [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine), [Azure Kubernetes Service (AKS)](https://azure.microsoft.com/en-in/services/kubernetes-service/) and [Amazon Elastic Container Service for Kubernetes (Amazon EKS)](https://aws.amazon.com/eks/) clusters.

## License

BKPR is licensed under the [Apache License Version 2.0](LICENSE).

## Requirements

BKPR has been tested to work on a bare-minimum Kubernetes cluster with three kubelet nodes with 2 CPUs and 8GiB of RAM each.

## Kubernetes version support matrix

The following matrix shows which Kubernetes versions and platforms are supported:

| BKPR release |  AKS versions |  GKE versions |  EKS versions |
|--------------|---------------|---------------|---------------|
| `1.3`        | `1.11`-`1.12` | `1.11`-`1.12` | `1.11`        |
| `1.4`        | `1.14`-`1.15` | `1.14`-`1.15` | `1.14`        |

## Quickstart

Please use the [installation guide](docs/install.md) to install the `kubeprod` binary before installing BKPR to your cluster.

* [AKS Quickstart](docs/quickstart-aks.md)
* [GKE Quickstart](docs/quickstart-gke.md)
* [EKS Quickstart](docs/quickstart-eks.md)
* [Generic Quickstart (experimental)](docs/quickstart-generic.md)

## Frequently Asked Questions (FAQ)

See the separate [FAQ](docs/FAQ.md) and [roadmap](docs/roadmap.md) documents.

## Versioning

The versioning used in BKPR is described [here](docs/versioning.md).

## Components

BKPR leverages the following components to achieve its mission. For more in-depth documentation about them please read the [components](docs/components.md) documentation.

### Logging stack

* [Elasticsearch](docs/components.md#elasticsearch): A distributed, RESTful search and analytics engine
* [Fluentd](docs/components.md#fluentd): A data collector for unified logging layer
* [Kibana](docs/components.md#kibana): A visualization tool for Elasticsearch data

![Logging stack](docs/images/logging-stack.png)

### Monitoring stack

* [Prometheus](docs/components.md#prometheus): A monitoring system and time series database
* [Alertmanager](docs/components.md#alertmanager): An alert manager and router
* [Grafana](docs/components.md#grafana): An open source metric analytics & visualization suite

![Monitoring stack](docs/images/monitoring-stack.png)

### Ingress stack

* [NGINX Ingress Controller](docs/components.md#nginx-ingress-controller): A Controller to satisfy requests for Ingress objects
* [cert-manager](docs/components.md#cert-manager): A Kubernetes add-on to automate the management and issuance of TLS certificates from various sources
* [OAuth2 Proxy](docs/components.md#oauth2-proxy): A reverse proxy and static file server that provides authentication using Providers (Google, GitHub, and others) to validate accounts by email, domain or group
* [ExternalDNS](docs/components.md#externaldns): A component to synchronize exposed Kubernetes Services and Ingresses with DNS providers

![Ingress stack](docs/images/ingress-stack.png)

## Release compatibility

### Components version support

The following matrix shows which versions of each component are used and supported in the most recent releases of BKPR:

|                                              Component                                               | BKPR 1.3 | BKPR 1.4 |
|------------------------------------------------------------------------------------------------------|----------|----------|
| [Alertmanager](https://prometheus.io/docs/alerting/alertmanager/)                                    | `0.16.x` | `0.20.x` |
| [cert-manager](https://cert-manager.io/docs/)                                                        | `0.7.x`  | `0.12.x` |
| [configmap-reload](https://github.com/jimmidyson/configmap-reload)                                   | `0.2.2`  | `0.3.x`  |
| [Elasticsearch](https://www.elastic.co/products/elasticsearch)                                       | `6.7.x`  | `7.5.x`  |
| [Elasticsearch Curator](https://www.elastic.co/guide/en/elasticsearch/client/curator/5.8/about.html) | `5.7.x`  | `5.8.x`  |
| [Elasticsearch Exporter](https://github.com/justwatchcom/elasticsearch_exporter)                     | `1.0.1`  | `1.1.x`  |
| [ExternalDNS](https://github.com/kubernetes-sigs/external-dns)                                       | `0.5.x`  | `0.5.x`  |
| [Fluentd](https://www.fluentd.org/)                                                                  | `1.4.x`  | `1.8.x`  |
| [Grafana](https://grafana.com/)                                                                      | `6.5.x`  | `6.5.x`  |
| [Kibana](https://www.elastic.co/products/kibana)                                                     | `6.7.x`  | `7.5.x`  |
| [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)                               | `1.1.0`  | `1.9.x`  |
| [Node exporter](https://github.com/prometheus/node_exporter)                                         | `0.17.0` | `0.18.x` |
| [NGINX Ingress Controller](https://github.com/kubernetes/ingress-nginx)                              | `0.24.x` | `0.26.x` |
| [oauth2_proxy](https://github.com/pusher/oauth2_proxy)                                               | `3.1.x`  | `4.1.x`  |
| [Prometheus](https://prometheus.io/)                                                                 | `2.8.x`  | `2.15.x` |

## Contributing

If you would like to become an active contributor to this project please follow the instructions provided in [contribution guidelines](CONTRIBUTING.md).

