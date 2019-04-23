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
| `0.3`        | `1.8`-`1.9`   | N/A           | N/A           |
| `1.1`        | `1.9`-`1.10`  | `1.9`-`1.10`  | N/A           |
| `1.1`        | `1.10`-`1.11` | `1.11`        | N/A           |
| `1.2`        | `1.10`-`1.11` | `1.11`        | `1.10`-`1.11` |
| `1.3`        | `1.11`-`1.12` | `1.11`-`1.12` | `1.11`        |

## Quickstart

Please use the [installation guide](docs/install.md) to install the `kubeprod` binary before installing BKPR to your cluster.

* [AKS Quickstart](docs/quickstart-aks.md)
* [GKE Quickstart](docs/quickstart-gke.md)
* [EKS Quickstart](docs/quickstart-eks.md)

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

|   Component   |    BKPR 1.0    | BKPR 1.1 | BKPR 1.2 | BKPR 1.3 |
|---------------|----------------|----------|----------|----------|
| Alertmanager  | `0.15.x`       | `0.15.x` | `0.16.x` | `0.16.x` |
| cert-manager  | `0.5.x`        | `0.5.x`  | `0.6.x`  | `0.7.x`  |
| Elasticsearch | `5.6.x`        | `5.6.x`  | `6.6.x`  | `6.7.x`  |
| ExternalDNS   | `0.5.x`        | `0.5.x`  | `0.5.x`  | `0.5.x`  |
| Fluentd       | `1.2.x`        | `1.3.x`  | `1.4.x`  | `1.4.x`  |
| Heapster      | `1.5.x`        | `N/A`    | `N/A`    | `N/A`    |
| Kibana        | `5.6.x`        | `5.6.x`  | `6.6.x`  | `6.7.x`  |
| nginx-ingress | `0.19.x`       | `0.21.x` | `0.23.x` | `0.24.x` |
| oauth2_proxy  | `0.20180625.x` | `3.0.x`  | `3.1.x`  | `3.1.x`  |
| Prometheus    | `2.3.x`        | `2.6.x`  | `2.7.x`  | `2.8.x`  |

## Contributing

If you would like to become an active contributor to this project please follow the instructions provided in [contribution guidelines](CONTRIBUTING.md).

