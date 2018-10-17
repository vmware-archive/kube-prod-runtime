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
* Create environment variables for the cluster name, resource group and DNS zone, as shown below:

  ```bash
  export AKS_CLUSTER_NAME=my-aks-cluster
  export AZURE_RESOURCE_GROUP_NAME=my-kubeprod-group
  export AZURE_DNS_ZONE=example.com
  ```

  The `AKS_CLUSTER_NAME` variable sets the name of the AKS cluster, `AZURE_RESOURCE_GROUP_NAME` specifies the name of the Azure resource group under which the cluster will be created, and `AZURE_DNS_ZONE` specifies the DNS suffix for the externally-visible websites and services deployed in the cluster.

  Update the values of these environment variables as per your requirements. The remaining steps will assume the values shown above.

* List your Microsoft Azure subscriptions:

  ```bash
  az account list -o table
  ``` 

* Set the default subscription account:

  ```bash
  az account set --subscription <azure-subscription-id>
  ```

  If your Azure account has more than one subscription, set the default subscription for future operations. Update the `<azure-subscription-id>` placeholder in the command above with the ID of the subscription you’d like to use.

* Create the resource group for AKS:

  ```bash
  az group create --name ${AZURE_RESOURCE_GROUP_NAME} --location <azure-region>
  ```

  Update the `<azure-region>` placeholder in the command above with the Azure region code (eg. `eastus`).

* Create the AKS cluster:

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

* Configure `kubectl` to use the new cluster:

  ```bash
  az aks get-credentials \
    --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
    --name "${AKS_CLUSTER_NAME}"
  ```

  This command configures the AKS cluster in `~/.kube/config` using the name specified by `${AKS_CLUSTER_NAME}` and makes it the default context.

* Verify that your cluster is up and running:

  ```bash
  kubectl get nodes
  ```

## Step 2: Install `kubeprod`
In this section, you will install the `kubeprod` binary on your local system. You have the option of either downloading and installing a pre-compiled binary or building the binary from source.

### Install a pre-compiled `kubeprod` binary

Download the latest release of the `kubeprod` binary and the accompanying manifests and add it to your `$PATH`.

### Build `kubeprod` from source

Alternatively, if you have access to the BKPR project repository, you may choose to build the `kubeprod` binary from the source code.

#### Prerequisites

* [Git](https://git-scm.com/downloads)
* [Make](https://www.gnu.org/software/make/)
* [Go programming language](https://golang.org/dl/)

#### Build instructions

* Set up your environment variables:

  ```bash
  export GOPATH=$HOME/go
  export PATH=$GOPATH/bin:$PATH
  export BKPR_SRC=$GOPATH/src/github.com/bitnami/kube-prod-runtime
  ```

* Download the BKPR sources:

  ```bash
  git clone git@github.com:bitnami/kube-prod-runtime.git $BKPR_SRC
  ```

* Build the `kubeprod` binary:

  ```bash
  cd $BKPR_SRC/kubeprod
  make
  ```

  By default, the `kubeprod` binary will be built at `$BKPR_SRC/kubeprod/bin/kubeprod`. We recommend moving it to `$GOPATH/bin`, or to a directory listed in the `$PATH` environment variable, like `/usr/local/bin`:

  ```bash
  mv $BKPR_SRC/kubeprod/bin/kubeprod $GOPATH/bin
  ```

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
    --manifests $BKPR_SRC/manifests \
    --platform aks+k8s-1.9 \
    --dns-zone "${AZURE_DNS_ZONE}" \
    --dns-resource-group "${AZURE_RESOURCE_GROUP_NAME}" 
  ```

  Replace the `<email-address>` placeholder in the above command with your valid email address. The email address is used by BKPR in requests to Let's Encrypt to issue TLS certificates for your domain.

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
