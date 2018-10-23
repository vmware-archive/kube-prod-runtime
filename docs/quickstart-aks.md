# Quickstart: BKPR on Azure Kubernetes Service (AKS)

## Introduction
The Bitnami Kubernetes Production Runtime (BKPR) makes it easy to run production workloads in Kubernetes by providing a collection of ready to run, pre-integrated services for logging, monitoring and certificate management and other infrastructure tools.

This document walks you through setting up an Azure Kubernetes Service (AKS) cluster and installing the Bitnami Kubernetes Production Runtime (BKPR) to that cluster.

## Prerequisites
* [Microsoft Azure account](https://azure.microsoft.com)
* [Microsoft Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

## Step 1: Set up the cluster
In this section, you will deploy an Azure Kubernetes Service (AKS) cluster using the Azure CLI.

* Log in to your Microsoft Azure account by executing `az login`. Follow the onscreen instructions to complete the login process.
* Configure the following  environment variables:

  ```bash
  export AZURE_SUBSCRIPTION_ID="xxxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  export AZURE_REGION="eastus"
  export AZURE_RESOURCE_GROUP=my-kubeprod-group
  export AZURE_DNS_ZONE=example.com
  export AZURE_AKS_CLUSTER=my-aks-cluster
  export AZURE_AKS_K8S_VERSION=1.9.11
  ```

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
    --node-count 3 \
    --node-vm-size Standard_DS2_v2 \
    --ssh-key-value ~/.ssh/id_rsa.pub \
    --kubernetes-version ${AZURE_AKS_K8S_VERSION} --verbose
  ```

  - `--node-count`: Number of nodes in the Kubernetes node pool.
  - `--node-vm-size`: Size of Virtual Machines to create as Kubernetes nodes.
  - `--ssh-key-value`: Public key path or key contents to install on node VMs for SSH access.

  The command assumes the user's public SSH key is located at `~/.ssh/id_rsa.pub`. Update the `--ssh-key-value` argument if you would like to use a different key.

  Provisioning a AKS cluster can take a long time to complete. Please be patient while the request is being processed.

* Configure `kubectl` to use the new cluster:

  ```bash
  az aks get-credentials \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${AZURE_AKS_CLUSTER}"
  ```

  This command configures the AKS cluster in `~/.kube/config` using the name specified by `${AZURE_AKS_CLUSTER}` and makes it the default context.

* Verify that your cluster is up and running:

  ```bash
  kubectl get nodes
  ```

## Step 2: Download BKPR
A BKPR release consists of a collection of Kubernetes manifests written in Jsonnet plus the accompanying `kubeprod` installer binary. The kubeprod binary deals with all the platform-specific details, evaluates the Jsonnet manifests, and applies them to the existing Kubernetes cluster.

BKPR releases are available for 64-bit versions of Linux, macOS and Windows platforms. Download the latest stable version for your platform of choice from the [releases](https://github.com/bitnami/kube-prod-runtime/releases) page.

To download BKPR release `vX.Y.Z`, for example:

On Linux:

  ```bash
  curl -LO https://github.com/bitnami/kube-prod-runtime/releases/download/vX.Y.Z/bkpr-vX.Y.Z-linux-amd64.tar.gz
  tar xf bkpr-vX.Y.Z-linux-amd64.tar.gz
  ```

On macOS:

  ```bash
  curl -LO https://github.com/bitnami/kube-prod-runtime/releases/download/vX.Y.Z/bkpr-vX.Y.Z-darwin-amd64.tar.gz
  tar xf bkpr-vX.Y.Z-darwin-amd64.tar.gz
  ```

To install the `kubeprod` binary:

  ```bash
  chmod +x bkpr-vX.Y.X/kubeprod
  sudo mv bkpr-vX.Y.X/kubeprod /usr/local/bin/
  ```

The Jsonnet manifests from the release will be used in the next step.

### Step 3: Deploy BKPR
BKPR bootstraps your AKS cluster with pre-configured services that make it easier to run, manage and monitor production workloads on Kubernetes. BKPR includes deployment extensions to automatically provide valid [Let's Encrypt TLS certificates](https://letsencrypt.org/) for apps and services running in your cluster, as well as to automatically configure logging and monitoring services for your Kubernetes workloads.

Follow the steps below:

* Create a directory where `kubeprod` will deploy the following files:

  * `kubeprod-manifest.jsonnet`: The cluster-specific entry point which is used by `kubeprod` and `kubecfg`
  * `kubeprod-autogen.json`: A JSON configuration file for the cluster. This file might contain sensitive information (secrets, passwords, tokens, etc.) so it is highly recommended to not store it under any revision control system.

  When `kubeprod` runs, it performs various platform-specific steps. For example, when bootstrapping BKPR on an AKS cluster, `kubeprod`  creates some Kubernetes objects in Azure. [Find more detailed information about these objects](aks/objects.md). Subsequently, `kubeprod` generates the `kubeprod-manifest.jsonnet` and `kubeprod-autogen.json` files and then performs a `kubecfg update` using the cluster-specific `kubeprod-manifest.jsonnet` file generated as the entry point. BKPR deploys everything into the `kubeprod` namespace.

* Run `kubeprod` from the directory you just created:

  ```bash
  kubeprod install aks \
    --email <email-address> \
    --manifests <path-to-jsonnet-manifests>/manifests \
    --dns-zone "${AZURE_DNS_ZONE}" \
    --dns-resource-group "${AZURE_RESOURCE_GROUP}"
  ```

  Replace `<path-to-jsonnet-manifests>` with the path to the BKPR release manifests directory extracted in the previous step. Additionally replace the `<email-address>` placeholder in the above command with your valid email address. The email address is used by BKPR in requests to Let's Encrypt to issue TLS certificates for your domain.

* Once BKPR has been deployed to your cluster, wait for all pods to start running and all TLS certificates to be issued before using BKPR.  To check that all pods are running, use the command below:

  ```bash
  kubectl get pods -n kubeprod
  ```

  BKPR uses `cert-manager` to requests TLS certificates for Kibana and Prometheus. To check the certificate objects that were created, use the command below:

  ```console
  kubectl get certificates -n kubeprod
  NAME                 AGE
  kibana-logging-tls   3h
  prometheus-tls       3h
  ```

  To check whether the TLS certificates have been successfully issued, use the command below:

  ```console
  kubectl describe certificate -n kubeprod kibana-logging-tls
  ...
    Conditions:
      Last Transition Time:  2018-07-06T09:58:34Z
      Message:               Certificate issued successfully
      Reason:                CertIssued
      Status:                True
      Type:                  Ready
  ...
  ```

* The final step is to update DNS records. The `kubeprod install aks` command sets up a DNS zone for your domain (specified in the `AZURE_DNS_ZONE` environment variable) if it doesn't exist yet. Then, it writes a list of nameservers to the standard output. You must use these nameservers to set up DNS records for your domain. For example:

  ```console
  INFO  You will need to ensure glue records exist for example.com pointing to NS [ns1-01.azure-dns.com. ns2-01.azure-dns.net. ns3-01.azure-dns.org. ns4-01.azure-dns.info.]
  ```

  Ensure you have updated these records at the domain registrar before proceeding. This is a required step for the automatic TLS certificate provisioning.

## Step 4: Use logging and monitoring
BKPR pre-configures an ELK stack for log collection, visualization and analysis. The Kibana dashboard can be accessed by visiting `https://kibana.${AZURE_DNS_ZONE}` in your Web browser.

Prometheus metrics collection is also configured for performance monitoring. The Prometheus dashboard can be accessed by visiting `https://prometheus.${AZURE_DNS_ZONE}`.
