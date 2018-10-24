# Bitnami Kubernetes Production Runtime

## Description

The Bitnami Kubernetes Production Runtime (BKPR) is a collection of services that makes it easy to run production workloads in Kubernetes.

Think of Bitnami Kubernetes Production Runtime as a curated collection of the services you would need to deploy on top of your Kubernetes cluster to enable logging, monitoring, certificate management, automatic discovery of Kubernetes resources via public DNS servers and other common infrastructure needs.

![BKPR](images/BKPR.png)

BKPR is available for [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine) and [Azure Kubernetes Service (AKS)](https://azure.microsoft.com/en-in/services/kubernetes-service/) clusters.

## License

BKPR is licensed under the [Apache License Version 2.0](LICENSE).

## Quickstart

* [AKS Quickstart](docs/quickstart-aks.md)
* GKE Quickstart

## Frequently Asked Questions (FAQ)

Please read the [FAQ](docs/FAQ.md).

## Versioning

The versioning used in BKPR is described [here](docs/versioning.md).

## Components

BKPR leverages the following components to achieve its mission. For more im-depth documentation about them please read the [components](docs/components.md) documentation.

### Monitoring
* [Prometheus](docs/components.md#user-content-prometheus): A monitoring system and time series database
* [Alertmanager](docs/components.md#user-content-alertmanager): An alert manager and router
### Logging
* [Elasticsearch](docs/components.md#user-content-elasticsearch): A distributed, RESTful search and analytics engine
* [Kibana](docs/components.md#user-content-kibana): A visualization tool for Elasticsearch data
* [Fluentd](docs/components.md#user-content-fluentd): A data collector for unified logging layer
### DNS and TLS certificates
* [ExternalDNS](docs/components.md#user-content-externaldns): A component to synchronize exposed Kubernetes Services and Ingresses with DNS providers
* [cert-manager](docs/components.md#user-content-cert-manager): A Kubernetes add-on to automate the management and issuance of TLS certificates from various sources
### Others
* [OAuth2 Proxy](docs/components.md#user-content-oauth2-proxy): A reverse proxy and static file server that provides authentication using Providers (Google, GitHub, and others) to validate accounts by email, domain or group
* [nginx-ingress](docs/components.md#user-content-nginx-ingress): A Controller to satisfy requests for Ingress objects

## Release compatibility

### Kubernetes version support matrix for BKPR 1.0

The following matrix shows which Kubernetes versions are supported in AKS and GKE in BKPR 1.0:

| Kubernetes version |  AKS  |  GKE  |
|:------------------:|:-----:|:-----:|
|        `1.9`       |  Yes  |  Yes  |
|        `1.10`      |  Yes  |  Yes  |

### Components version support

The following matrix shows which versions of each component are used and supported in the most recent releases of BKPR:

|   Component   |          BKPR 1.0  |
|:-------------:|-------------------:|
|   Prometheus  |            `2.3.2` |
|     Kibana    |           `5.6.12` |
| Elasticsearch |           `5.6.12` |
|  cert-manager |            `0.3.2` |
|  Alertmanager |           `0.15.2` |
|  ExternalDNS  |            `0.5.4` |
| nginx-ingress |           `0.19.0` |
|  oauth2_proxy | `0.20180625.74543` |
|    Heapster   |            `1.5.2` |
|    Fluentd    |            `1.2.2` |

## Contribute code

If you would like to become an active contributor to this project please follow the instructions provided in [contribution guidelines](CONTRIBUTING.md).
