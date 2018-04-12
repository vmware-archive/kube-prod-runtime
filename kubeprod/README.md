# Installer for Production Runtime

Usage:

```sh
# Find supported platform
kubeprod list-platforms

# Install to cluster given by current kubectl context
kubeprod install --platform=$platform
```

## Development

Requires a typical golang development environment.  To build:

```sh
go get github.com/bitnami/kube-prod-runtime/kubeprod
```

For local development against minikube:

```sh
minikube start --kubernetes-version=v1.9.0

./kubeprod -v install --platform=minikube-0.25+k8s-1.9 --manifests=../manifests
```
