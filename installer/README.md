# Installer for Production Runtime

Usage:

```sh
# Find supported platform
installer list-platforms

# Install to cluster given by current kubectl context
installer install --platform=$platform
```

## Development

Requires a typical golang development environment.  To build:

```sh
go get github.com/bitnami/kube-prod-runtime/installer
```

For local development against minikube:

```sh
minikube start --kubernetes-version=v1.9.0

./installer -v install --platform=minikube-0.25+k8s-1.9 --manifests=../manifests
```
