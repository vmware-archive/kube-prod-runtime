# Bitnami Production Runtime for Kubernetes

The Bitnami Kubernetes Production Runtime (BKPR) is a collection of services that makes it easy to run production workloads in Kubernetes.

Think of BKPR as a curated collection of the services you would need to deploy on top of your Kubernetes cluster to enable logging, monitoring, certificate management and other common infrastructure needs.

BKPR is available for GKE and AKS clusters.

## Quickstart

* [Quickstart in AKS](docs/quickstart-aks.md)
* Quickstart in GKE

## Frequently Asked Questions (FAQ)

Please read the [FAQ](docs/FAQ.md).

## Versioning

The versioning used in BKPR is described [here](docs/versioning.md).

## Components

### Monitoring
* [Prometheus](https://prometheus.io/). A monitoring system and time series database
* [Alertmanager](https://prometheus.io/docs/alerting/alertmanager/). An alert manager and router
### Logging
* [Elasticsearch](https://www.elastic.co/products/elasticsearch). A distributed, RESTful search and analytics engine
* [Kibana](https://www.elastic.co/products/kibana). A visualization tool for Elasticsearch data
* [Fluentd](https://www.fluentd.org/). A data collector for unified logging layer
### DNS and TLS certificates
* [ExternalDNS](https://github.com/kubernetes-incubator/external-dns). ExternalDNS synchronizes exposed Kubernetes Services and Ingresses with DNS providers
* [cert-manager](https://github.com/jetstack/cert-manager). A Kubernetes add-on to automate the management and issuance of TLS certificates from various issuing sources
### Others
* [OAuth2 Proxy](https://github.com/bitnami/bitnami-docker-oauth2-proxy). A reverse proxy and static file server that provides authentication using Providers (Google, GitHub, and others) to validate accounts by email, domain or group
* [nginx-ingress](https://github.com/kubernetes/ingress-nginx). A Controller to satisfy requests for Ingress objects

## Release Compatibility

### Kubernetes Version Support

TBA - Including a matrix of compatibility of BKPR versions and Kubernetes versions

### Components Version Support

TBA - Including a matrix that matches BKPR versions with the versions of the components
