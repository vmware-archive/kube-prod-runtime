# BKPR on Azure Kubernetes Service

## Introduction
The Bitnami Kubernetes Production Runtime (BKPR) makes it easy to run production workloads in Kubernetes by providing a collection of ready to run, pre-integrated services for logging, monitoring and certificate management and other infrastructure tools.

This document walks through setting up an AKS cluster and installing the Bitnami Kubernetes Production Runtime (BKPR) in the cluster.

## Prerequisites
* [Microsoft Azure account](https://azure.microsoft.com)
* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

## Cluster setup
In this section we deploy an Azure Kubernetes Service (AKS) cluster using the Azure CLI.

* Login to your azure account by executing `az login` and follow the onscreen instructions to complete the login.
* Create environment variables for the cluster name, resource group and DNS zone

```bash
export AKS_CLUSTER_NAME=my-aks-cluster
export AZURE_RESOURCE_GROUP_NAME=my-kubeprod-group
export AZURE_DNS_ZONE=example.com
```

The value of `AKS_CLUSTER_NAME` is used to set the name of the AKS cluster, `AZURE_RESOURCE_GROUP_NAME` specifies the name of the Azure resource group under which the cluster will be created and the `AZURE_DNS_ZONE` specifies the DNS suffix for the externally visible websites and services deployed in the cluster.

Please update the values of these environment variables as per your requirements. In the remainder of this document we will assume the above configuration for convenience.

* List your azure subscriptions

```bash
az account list -o table
``` 

* Set the default subscription account

```bash
az account set --subscription <azure-subscription-id>
```

If your Azure account is subscribed to more than one subscription it's convenient to set the default subscription ID. Update the `<azure-subscription-id>` placeholder in the command above with the ID of the subscription you’d like to use.

* Create the resource group for AKS

```bash
az group create --name ${AZURE_RESOURCE_GROUP_NAME} --location <azure-region>
```

Update the `<azure-region>` placeholder in the command above with the Azure region code (eg. `eastus`) for creation of the Azure Resource Group.

* Create the AKS cluster

```bash
az aks create \
  --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
  --name "${AKS_CLUSTER_NAME}" \
  --node-count 3 \
  --node-vm-size Standard_DS2_v2 \
  --ssh-key-value ~/.ssh/id_rsa.pub \
  --kubernetes-version 1.9.10 --verbose
```

Provisioning a AKS cluster can take a long time to complete. Please be patient while the request is being processed.

* Configure `kubectl` to use the new cluster

```bash
az aks get-credentials \
  --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
  --name "${AKS_CLUSTER_NAME}"
```

This command configures the AKS cluster in `~/.kube/config` using the name specified by `${AKS_CLUSTER_NAME}` and makes it the default context.

* Verify that your cluster is up and running

```bash
kubectl get nodes
```

## Installing BKPR
In this section we walk through building the kubeprod binary and use it to install the BKPR components to the AKS cluster.

### Install the `kubeprod` binary

Download the latest release of the `kubeprod` binary and the accompanying manifests and add it to your `$PATH`.

### Building `kubeprod` from source

Alternatively, if you have access to the BKPR project repository, you may choose to build the `kubeprod` binary instead of using a pre-built binary, as described in the next section. You may skip this section if you are using a binary distribution of BKPR.

#### Prerequisites

* [Git](https://git-scm.com/downloads)
* [Make](https://www.gnu.org/software/make/)
* [Go programming language](https://golang.org/dl/)

#### Build instructions

* Set up your environment variables

```bash
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$PATH
export BKPR_SRC=$GOPATH/src/github.com/bitnami/kube-prod-runtime
```

* Download the BKPR sources

```bash
git clone git@github.com:bitnami/kube-prod-runtime.git $BKPR_SRC
```

* Build the `kubeprod` binary

```bash
cd $BKPR_SRC/kubeprod
make
```

The `kubeprod` binary will be located at `$BKPR_SRC/kubeprod/bin/kubeprod`, and we recommend to move it under `$GOPATH/bin`:

```bash
mv $BKPR_SRC/kubeprod/bin/kubeprod $GOPATH/bin
```

Alternatively, move the `kubeprod` binary into a directory listed in the `$PATH` environment variable, like `/usr/local/bin`.

### Deploy BKPR
BKPR bootstraps your AKS cluster with pre-configured services that make it easier to run, manage and monitor production workloads on Kubernetes. BKPR includes deployment extensions to automatically provide valid LetsEncrypt TLS certificates for apps and services running in your cluster as well as automatically configure logging and monitoring services for your Kubernetes workloads.

Before running `kubeprod` to bootstrap BKPR, create a directory where `kubeprod` will deploy the following files:

* `kube-system.jsonnet`: the cluster-specific entry point which is used by `kubeprod` and `kubecfg`
* `kubeprod.json`: a JSON configuration file for the cluster. This file might contain sensitive information (secrets, passwords, tokens, etc.) so it is highly recommended to not store it under any revision control system.

When `kubeprod` runs, it performs some platform-specific steps. For example, when bootstrapping BKPR in AKS (Azure Kubernetes), `kubeprod` will create some objects in Azure. For more detailed information about these objects, refer to [here](aks/objects.md).

Afterwards, `kubeprod` generates the `kube-system.jsonnet` and `kubeprod.json` files and then will perform a `kubecfg update` using the cluster-specific `kube-system.jsonnet` file generated as the entry point.

Run `kubeprod` from the directory you just created.

```bash
kubeprod install aks \
  --email <email-address> \
  --manifests $BKPR_SRC/manifests \
  --platform aks+k8s-1.9 \
  --dns-zone "${AZURE_DNS_ZONE}" \
  --dns-resource-group "${AZURE_RESOURCE_GROUP_NAME}" 
```

Replace the `<email-address>` in the above command with your valid email address. The email address is used by BKPR in requests to Let's Encrypt to issue TLS certificates for your domain.

Once BKPR has been deployed to your cluster, you will need to wait for all pods to be running and TLS certificates to be issued to be able to use BKPR. BKPR deploys everything into the `kube-system` namespace. Check that all pods are successfully running:

```bash
kubectl get pods -n kube-system
``` 

BKPR uses `cert-manager` to requests TLS certificates for Kibana and Prometheus. You can check the certificates objects that were created:

```console
kubectl get certificates -n kube-system
NAME                 AGE
kibana-logging-tls   3h
prometheus-tls       3h
```
 
And check whether the TLS certificates were already successfully issued:

```console
kubectl describe certificate -n kube-system kibana-logging-tls
...
  Conditions:
    Last Transition Time:  2018-07-06T09:58:34Z
    Message:               Certificate issued successfully
    Reason:                CertIssued
    Status:                True
    Type:                  Ready
...
```

* Update DNS records
The `kubeprod install aks` command from the previous step sets up a DNS zone for your domain (specified in the `AZURE_DNS_ZONE` environment variable) if it doesn't exist yet. Then, it writes to the standard output a list of nameservers which you need to set up NS records for your domain. For example:

```console
INFO  You will need to ensure glue records exist for example.com pointing to NS [ns1-01.azure-dns.com. ns2-01.azure-dns.net. ns3-01.azure-dns.org. ns4-01.azure-dns.info.]
```

Ensure you have updated these records at the domain registrar before proceeding. This is a required step for the automatic TLS certificate provisioning.

## Logging and Monitoring
BKPR pre-configures a ELK stack for log collection, visualization and analysis. The Kibana dashboard can be accessed by visiting `https://kibana.${AZURE_DNS_ZONE}` in your Web browser.

Prometheus metrics collection is also configured for performance monitoring and can be access by visiting `https://prometheus.${AZURE_DNS_ZONE}`.
