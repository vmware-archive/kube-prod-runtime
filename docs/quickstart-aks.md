# Quickstart: BKPR on Azure Kubernetes Service (AKS)

## Introduction

This document walks you through setting up an Azure Kubernetes Service (AKS) cluster and installing the Bitnami Kubernetes Production Runtime (BKPR) on the cluster.

## Prerequisites

* [Microsoft Azure account](https://azure.microsoft.com)
* [Microsoft Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
* [Kubernetes CLI](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [BKPR installer](install.md)
* [kubecfg](https://github.com/ksonnet/kubecfg/releases)
* [jq](https://stedolan.github.io/jq/)

## Installation and setup

### Step 1: Set up the cluster

In this section, you will deploy an Azure Kubernetes Service (AKS) cluster using the Azure CLI.

* Log in to your Microsoft Azure account by executing `az login` and follow the onscreen instructions.

* Configure the following environment variables:

  ```bash
  export BKPR_DNS_ZONE=my-domain.com
  export AZURE_USER=$(az account show --query user.name -o tsv)
  export AZURE_SUBSCRIPTION_ID=xxxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  export AZURE_REGION=eastus
  export AZURE_RESOURCE_GROUP=my-kubeprod-group
  export AZURE_AKS_CLUSTER=my-aks-cluster
  export AZURE_AKS_K8S_VERSION=1.9.11
  ```

  - `BKPR_DNS_ZONE` specifies the DNS suffix for the externally-visible websites and services deployed in the cluster.
  - `AZURE_USER` specifies the email address used in requests to Let's Encrypt.
  - `AZURE_SUBSCRIPTION_ID` specifies the Azure subscription id. `az account list -o table` lists your Microsoft Azure subscriptions.
  - `AZURE_REGION` specifies the Azure region code.
  - `AZURE_RESOURCE_GROUP` specifies the name of the Azure resource group in which resources should be created.
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

### Step 2: Deploy BKPR

To bootstrap your Kubernetes cluster with BKPR:

  ```bash
  kubeprod install aks \
    --email ${AZURE_USER} \
    --dns-zone "${BKPR_DNS_ZONE}" \
    --dns-resource-group "${AZURE_RESOURCE_GROUP}"
  ```

Wait for all the pods in the cluster to enter `Running` state:

  ```bash
  kubectl get pods -n kubeprod
  ```

### Step 3: Configure domain registration records

BKPR creates and manages a DNS zone which is used to map external access to applications and services in the cluster. However, for it to be usable, you need to configure the NS records for the zone.

Query the name servers of the zone with the following command and configure the records with your domain registrar.

  ```bash
  az network dns zone show \
    --name ${BKPR_DNS_ZONE} \
    --resource-group ${AZURE_RESOURCE_GROUP} \
    --query nameServers -o tsv
  ```

Please note, it can take a while for the DNS changes to propagate.

### Step 4: Access logging and monitoring dashboards

After the DNS changes have propagated you should be able to access the Prometheus and Kibana dashboards by visiting `https://prometheus.${BKPR_DNS_ZONE}` and `https://kibana.${BKPR_DNS_ZONE}` respectively.

Congratulations! You can now deploy your applications on the Kubernetes cluster and BKPR will help you manage and monitor them effortlessly.

## Next steps

- [Installing Kubeapps on BKPR](kubeapps-on-bkpr.md)

## Teardown and cleanup

### Step 1: Uninstall BKPR from your cluster

  ```bash
  kubecfg delete kubeprod-manifest.jsonnet
  ```

### Step 2: Delete the Azure DNS zone

  ```bash
  az network dns zone delete \
    --name ${BKPR_DNS_ZONE} \
    --resource-group ${AZURE_RESOURCE_GROUP}
  ```

  Additionally you should remove the NS entries configured at the domain registrar.

### Step 3: Delete Azure app registrations

  ```bash
  az ad app delete \
    --subscription ${AZURE_SUBSCRIPTION_ID} \
    --id $(jq -r .externalDns.aadClientId kubeprod-autogen.json)
  az ad app delete \
    --subscription ${AZURE_SUBSCRIPTION_ID} \
    --id $(jq -r .oauthProxy.client_id kubeprod-autogen.json)
  ```

### Step 4: Delete the AKS cluster

  ```bash
  az aks delete \
    --name ${AZURE_AKS_CLUSTER} \
    --resource-group ${AZURE_RESOURCE_GROUP}
  ```

### Step 5: Delete the Azure resource group

  ```bash
  az group delete --name ${AZURE_RESOURCE_GROUP}
  ```
