# Install BKPR

A Bitnami Kubernetes Production Runtime (BKPR) release consists of a collection of Kubernetes manifests written in Jsonnet plus the accompanying `kubeprod` installer binary. The `kubeprod` binary deals with all the platform-specific details, evaluates the Jsonnet manifests, and applies them to the existing Kubernetes cluster.

This document walks you through installing the `kubeprod` binary.

## Install `kubeprod`

The `kubeprod` binary can be installed from pre-built binary releases or can be built directly from source.

### Install from binary releases

BKPR releases are available for 64-bit versions of Linux, macOS and Windows platforms. Download the latest stable version for your platform of choice from the [releases](https://github.com/bitnami/kube-prod-runtime/releases) page.

For convenience, let's define the `BKPR_VERSION` environment variable:

```bash
BKPR_VERSION=$(curl --silent "https://api.github.com/repos/bitnami/kube-prod-runtime/releases/latest" | jq -r '.tag_name')
```

_The command configures the `BKPR_VERSION` variable with the latest stable version of BKPR. If you wish to use a pre-release or a specific version, please set it up accordingly._

1. Use the following commands to download the desired release:

On Linux:

  ```bash
  curl -LO https://github.com/bitnami/kube-prod-runtime/releases/download/${BKPR_VERSION}/bkpr-${BKPR_VERSION}-linux-amd64.tar.gz
  tar xf bkpr-${BKPR_VERSION}-linux-amd64.tar.gz
  ```

On macOS:

  ```bash
  curl -LO https://github.com/bitnami/kube-prod-runtime/releases/download/${BKPR_VERSION}/bkpr-${BKPR_VERSION}-darwin-amd64.tar.gz
  tar xf bkpr-${BKPR_VERSION}-darwin-amd64.tar.gz
  ```

2. Install `kubeprod` with the commands below:

  ```bash
  chmod +x bkpr-${BKPR_VERSION}/kubeprod
  sudo mv bkpr-${BKPR_VERSION}/kubeprod /usr/local/bin/
  ```

### Build from source (Linux / macOS)

To build the `kubeprod` binary from source you need the [Go](https://golang.org/) compiler. Please follow the [Go install guide](https://golang.org/doc/install) to install the compiler on your machine before proceeding with this section.

1. Set up the Go environment variables:

  ```bash
  export GOPATH=$HOME/go
  export PATH=$GOPATH/bin:$PATH
  ```

2. Build `kubeprod`:

  ```bash
  go get github.com/bitnami/kube-prod-runtime/kubeprod
  ```

  The `kubeprod` binary will be installed at `$GOPATH/bin/kubeprod`.

# Next Steps

You can now use the `kubeprod` installer to deploy BKPR on your Kubernetes cluster by following the quickstart guides linked below.

- [Quickstart: BKPR on Azure Kubernetes Service (AKS)](quickstart-aks.md)
- [Quickstart: BKPR on Google Kubernetes Engine (GKE)](quickstart-gke.md)
- [Quickstart: BKPR on Amazon Elastic Container Service for Kubernetes (EKS)](quickstart-eks.md)
- [Quickstart: BKPR on Generic Kubernetes Cluster (Generic)](quickstart-generic.md)
