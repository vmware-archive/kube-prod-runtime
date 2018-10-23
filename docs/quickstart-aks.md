# Quickstart: BKPR on Azure Kubernetes Service (AKS)

## Introduction

This document walks you through setting up an Azure Kubernetes Service (AKS) cluster and installing the Bitnami Kubernetes Production Runtime (BKPR) to that cluster.

## Prerequisites

* [Microsoft Azure account](https://azure.microsoft.com)
* [Microsoft Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [kubecfg](https://github.com/ksonnet/kubecfg/releases)

## Installation and setup

### Step 1: Set up the cluster

In this section, you will deploy an Azure Kubernetes Service (AKS) cluster using the Azure CLI.

* Log in to your Microsoft Azure account by executing `az login` and follow the onscreen instructions.

* Configure the following environment variables:

  ```bash
  export AZURE_USER=$(az account show --query user.name -o tsv)
  export AZURE_SUBSCRIPTION_ID=xxxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  export AZURE_REGION=eastus
  export AZURE_RESOURCE_GROUP=my-kubeprod-group
  export AZURE_DNS_ZONE=my-domain.com
  export AZURE_AKS_CLUSTER=my-aks-cluster
  export AZURE_AKS_K8S_VERSION=1.9.11
  ```

  - `AZURE_USER` specifies the email address used in requests to Let's Encrypt.
  - `AZURE_SUBSCRIPTION_ID` specifies the Azure subscription id. `az account list -o table` lists your Microsoft Azure subscriptions.
  - `AZURE_REGION` specifies the Azure region code.
  - `AZURE_RESOURCE_GROUP` specifies the name of the Azure resource group in which resources should be created.
  - `AZURE_DNS_ZONE` specifies the DNS suffix for the externally-visible websites and services deployed in the cluster.
  - `AZURE_AKS_CLUSTER` specifies the name of the AKS cluster.
  - `AZURE_AKS_K8S_VERSION` specifies the version of Kubernetes to use for creating the cluster. The [BKPR Kubernetes version support matrix](../README.md#kubernetes-version-support-matrix-for-bkpr-10) lists the base Kubernetes versions supported by BKPR. `az aks get-versions --location ${AZURE_REGION} -o table` lists the versions available in your region.

* Set the default subscription account:

  ```bash
  az account set --subscription ${AZURE_SUBSCRIPTION_ID}
  ```

* Create the resource group for AKS:

  ```bash
  az group create --name ${AZURE_RESOURCE_GROUP} --location ${AZURE_REGION}
  ```

* Create the AKS cluster:

  ```bash
  az aks create \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${AZURE_AKS_CLUSTER}" \
    --kubernetes-version ${AZURE_AKS_K8S_VERSION} --verbose
  ```

  Provisioning a AKS cluster can take a long time to complete. Please be patient while the request is being processed.

* Configure `kubectl` to use the new cluster:

  ```bash
  az aks get-credentials \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${AZURE_AKS_CLUSTER}" \
    --overwrite-existing
  ```

* Verify that your cluster is up and running:

  ```bash
  kubectl get nodes
  ```

### Step 2: Download BKPR

BKPR releases are available for 64-bit versions of Linux, macOS and Windows platforms. Download the latest stable version for your platform of choice from the [releases](https://github.com/bitnami/kube-prod-runtime/releases) page.

For convenience lets define a environment variable with the BKPR version:

```bash
export BKPR_VERSION=vX.Y.Z
```

_Update `vX.Y.Z` with the actual BKPR version. Ideally this would be the most recent release._

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

To install the `kubeprod` binary:

  ```bash
  chmod +x bkpr-${BKPR_VERSION}/kubeprod
  sudo mv bkpr-${BKPR_VERSION}/kubeprod /usr/local/bin/
  ```

Note: The Jsonnet manifests from the release are used in the next step.

### Step 3: Deploy BKPR

To bootstrap your Kubernets cluster with BKPR:

  ```bash
  kubeprod install aks \
    --email ${AZURE_USER} \
    --manifests ./bkpr-${BKPR_VERSION}/manifests \
    --dns-zone "${AZURE_DNS_ZONE}" \
    --dns-resource-group "${AZURE_RESOURCE_GROUP}"
  ```

Wait for all the pods in the cluster to enter `Running` state:

  ```bash
  kubectl get pods -n kubeprod
  ```

### Step 4: Registrar setup

BKPR creates and manages a DNS zone which is used to map external access to applications and services in the cluster. However to be usable you need to configure the NS records for the zone.

Query the name servers of the zone with the following command and configure the records with your domain registrar.

  ```bash
  az network dns zone show \
    --name ${AZURE_DNS_ZONE} \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --query nameServers -o tsv
  ```

Please note, it can take a while for the DNS changes to propogate.

### Step 5: Access logging and monitoring dashboards

After the DNS changes have propagated you should be able to access the Prometheus and Kibana dashboards by visiting `https://prometheus.${AZURE_DNS_ZONE}` and `https://kibana.${AZURE_DNS_ZONE}` respectively.

Congratulations! You can now deploy your applications on the Kubernetes cluster and BKPR will help you manage and monitor them effortlessly.

## Teardown and cleanup

### Step 1: Uninstall BKPR from your cluster

  ```bash
  kubecfg delete kubeprod-manifest.jsonnet
  ```

### Step 2: Delete the Azure DNS zone

  ```bash
  az network dns zone delete \
    --name ${AZURE_DNS_ZONE} \
    --resource-group ${AZURE_RESOURCE_GROUP}
  ```

  Additionally you should remove the NS entries configured at the domain registrar.

### Step 3: Delete the AKS cluster

  ```bash
  az aks delete \
    --name ${AZURE_AKS_CLUSTER} \
    --resource-group ${AZURE_RESOURCE_GROUP}
  ```

### Step 4: Delete the Azure resource group

  ```bash
  az group delete --name ${AZURE_RESOURCE_GROUP}
  ```
