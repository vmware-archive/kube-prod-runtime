# Application Developer's Reference Guide

This document is intended for cloud-native application developers targeting application deployments on Bitnami Kubernetes Production Runtime (BKPR). It describes the configuration they need to perform for automating the Ingress, TLS, logging and monitoring support for their application.

## Introduction

BKPR is a curated collection of services running on top of your existing Kubernetes cluster with the aim of automating the configuration of public access, logging and monitoring, and management of DNS records and TLS certificates.

For BKPR to perform this automation, you need to apply a few configuration changes in Kubernetes manifests of your application. The following sections walk you through each of these changes.

## Ingress and Let's Encrypt

BKPR installs an [NGINX controller](https://github.com/kubernetes/ingress-nginx) which provides load balancing, SSL termination and name-based virtual hosting for your applications. Ingress enables you to expose HTTP and HTTPS routes from outside the cluster to services running inside the cluster.

BKPR performs DNS zone record updates for host entries present in [ingress rules](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-rules) automatically without any additional configurations.

To automate the Let's Encrypt certificate provisioning you should add the annotation `kubernetes.io/tls-acme: "true"` to the Ingress resource of your application. Optionally you could add the annotation `kubernetes.io/ingress.class: "nginx"` to designate that the Ingress resource should only be handled by the NGINX controller.

For example, with the following snippet for a Kubernetes Ingress resource, BKPR will automatically update the DNS records for `myapp.mydomain.com` and request Let's Encrypt for a valid TLS certificate for your application, following which you would be able to access the application securely over the Internet.

```yaml
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: "myapp-ingress"
  labels:
    name: "myapp"
  annotations:
    kubernetes.io/ingress.class: "nginx"
    kubernetes.io/tls-acme: "true"
spec:
  tls:
  - hosts:
    - myapp.mydomain.com
    secretName: myapp-tls
  rules:
  - host: myapp.mydomain.com
    http:
      paths:
        - path: /
          backend:
            serviceName: myapp-svc
            servicePort: 80
```

## Restricting access with OAuth Authentication

BKPR installs a [OAuth2 Proxy](https://github.com/pusher/oauth2_proxy/) for restricting access to the BKPR dashboards.

Externally accessible web applications deployed by users on the cluster are not protected by this OAuth scheme. However you can easily enable this by adding the following annotations to your applications `Ingress` resources.

```yaml
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: my-app
  annotations:
    nginx.ingress.kubernetes.io/auth-signin: https://auth.my-bkpr-domain.com/oauth2/start?rd=%2F$server_name$escaped_request_uri
    nginx.ingress.kubernetes.io/auth-url: https://auth.my-bkpr-domain.com/oauth2/auth
```

After these changes are applied, users would be required to authenticate themselves with the OAuth server to gaining access to the application interface.

## Logging

BKPR installs [Elasticsearch](https://elastic.co/products/elasticsearch) in the cluster which provides a RESTful search and analytics engine for processing your application logs. The Elasticsearch stack uses [Fluentd](https://www.fluentd.org/) to capture the standard output of every container running in the cluster and persistent storage to store historical data of the cluster container logs.

For Fluentd to be able to capture your applications logs, as a cloud-native application developer, all you need to do is configure your application to output the logs to the standard output of the application container.

[Kibana](https://www.elastic.co/products/kibana) installed in the cluster lets you visualize your Elasticsearch data and navigate the Elasticsearch stack. You can use it to debug your application when any abnormal application behavior is noticed.

## Monitoring

Instrumentation and monitoring in BKPR is made possible by [Prometheus](https://prometheus.io/) which is a popular open-source monitoring system and time series database written in Go.

By default, BKPR collects a lot of instrumentation data about your cluster. As a cloud-native application developer, you should instrument your application code to take advantage of the built in monitoring so that you are alerted when abnormal application behavior is detected. Please refer to the official Prometheus documentation to learn about [writing exporters](https://prometheus.io/docs/instrumenting/writing_exporters/).

If your application exports instrumentation data, specify the `prometheus.io/scrape: "true"` annotation so that the instrumentation data is scraped by Prometheus. Additionally you can specify the annotations `prometheus.io/port` to specify the port for the metrics endpoint and `prometheus.io/path` to specify the path of the metrics endpoint.

For example, with the following snippet for a Kubernetes Service resource, Prometheus will automatically scrape instrumentation data from your application by connecting to port `9104` of the service at the `/metrics` request path.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: "myapp-svc"
  labels:
    name: "myapp"
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "9104"
    prometheus.io/path: "/metrics"
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: http
  selector:
    name: "myapp"
```
