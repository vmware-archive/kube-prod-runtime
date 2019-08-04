# Quickstart: BKPR on Azure Kubernetes Service (AKS)

## TOC

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Installation and setup](#installation-and-setup)
- [Next steps](#next-steps)
  + [Installing Kubeapps on BKPR](kubeapps-on-bkpr.md)
- [Upgrading](#upgrading)
- [Teardown and cleanup](#teardown-and-cleanup)
- [Further reading](#further-reading)

## Introduction

This document walks you through setting up an VMware Cloud PKS (cPKS) cluster and installing the Bitnami Kubernetes Production Runtime (BKPR) on it.

## Prerequisites

* [VMware Cloud account](https://cloud.vmware.com/)
* VMware Cloud PKS CLI for [macOS](https://s3.amazonaws.com/vke-cli-us-east-1/latest/mac/vke) or [Linux](https://s3.amazonaws.com/vke-cli-us-east-1/latest/linux64/vke) or [Windows](https://s3.amazonaws.com/vke-cli-us-east-1/latest/windows64/vke.exe)
* [Kubernetes CLI](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [BKPR installer](install.md)
* [`kubecfg`](https://github.com/ksonnet/kubecfg/releases)
* [`jq`](https://stedolan.github.io/jq/)

### DNS requirements

***this needs an update...***

~~In addition to the requirements listed above, a domain name is also required for setting up Ingress endpoints to services running in the cluster. The specified domain name can be a top-level domain (TLD) or a subdomain. In either case you have to manually [set up the NS records](#step-3-configure-domain-registration-records) for the specified TLD or subdomain so as to delegate DNS resolution queries to an Azure DNS zone created and managed by BKPR.  This is required in order to generate valid TLS certificates.~~

## Installation and setup

### Step 1: Set up the cluster

In this section, you will deploy a VMware Cloud PKS (cPKS) cluster using the Cloud PKS CLI.

* Log in to your VMware Cloud PKS account by executing `vke account login -t <organization-id> -r <refresh-token>`.  See [docs on login](https://www.google.com/url?sa=t&rct=j&q=&esrc=s&source=web&cd=1&cad=rja&uact=8&ved=2ahUKEwigtpX3_enjAhWZPM0KHVjOBJgQFjAAegQIABAB&url=https%3A%2F%2Fdocs.vmware.com%2Fen%2FVMware-Cloud-PKS%2Fservices%2Fcom.vmware.cloudpks.doc%2FGUID-FF001D2D-66BC-4837-AABF-AD4F9584A8DC.html&usg=AOvVaw3OFKtn_74DA1OVMoRcb10-) for more details.

* Configure the following environment variables:

  ```bash
  export BKPR_DNS_ZONE=my-domain.com
  export PKS_ENCRYPT_USER=someuser@my-domain.com
  export PKS_REGION=us-east-1 # use `vke info region list` to see available regions
  export PKS_FOLDER=SharedFolder
  export PKS_PROJECT=SharedProject
  export PKS_CLUSTER_TYPE=production # or development
  export PKS_CLUSTER=my-pks-cluster
  export PKS_K8S_VERSION=1.12.9-1 # see `vke cluster versions list --region ${PKS_REGION}` for version options
  ```

  - `BKPR_DNS_ZONE` specifies the DNS suffix for the externally-visible websites and services deployed in the cluster.
  - `PKS_ENCRYPT_USER` specifies the email address used in requests to Let's Encrypt.
  - `PKS_REGION` specifies the region to deploy a cluster into
  - `PKS_FOLDER` specifies the name of the folder in which resources should be created.
  - `PKS_PROJECT` specifies the name of the project in which resources should be created.
  - `PKS_CLUSTER` specifies the name of the cluster.
  - `PKS_K8S_VERSION` specifies the version of Kubernetes to use for creating the cluster. The [BKPR Kubernetes version support matrix](../README.md#kubernetes-version-support-matrix-for-bkpr-10) lists the base Kubernetes versions supported by BKPR. `vke cluster versions list --region ${PKS_REGION}` lists the versions available in your region.


* Create a smart cluster from the command line using the following.  [See the docs](https://docs.vmware.com/en/VMware-Cloud-PKS/services/com.vmware.cloudpks.doc/GUID-76505050-7D87-4C20-A82B-C1EF2E15253C.html) for more details.

  ```bash
  vke folder set ${PKS_FOLDER}
  vke project set ${PKS_PROJECT}
  vke cluster create --cluster-type ${PKS_CLUSTER_TYPE} --name ${PKS_CLUSTER} --region ${PKS_REGION} --version ${PKS_K8S_VERSION}
  ```

  Provisioning a cluster can take minutes to complete. Please be patient while the request is being processed.

* Configure `kubectl` to use the new cluster:

  ```bash
  vke cluster auth setup ${PKS_CLUSTER}
  ```

* Verify that your cluster is up and running:

  ```bash
  kubectl get nodes
  ```

### Step 2: Deploy BKPR

To bootstrap your Kubernetes cluster with BKPR:

  ```bash
  kubeprod install aks \
    --email "${PKS_ENCRYPT_USER}" \
    --dns-zone "${BKPR_DNS_ZONE}" \
    # TODO --dns-resource-group "${AZURE_RESOURCE_GROUP}"
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

The following screenshot illustrates the NS record configuration on a DNS registrar when a subdomain is used.

![Google Domains NS Configuration for subdomain](images/google-domains-aks-zone-ns-config.png)

Please note, it can take a while for the DNS changes to propagate.

### Step 4: Access logging and monitoring dashboards

After the DNS changes have propagated, you should be able to access the Prometheus, Kibana and Grafana dashboards by visiting `https://prometheus.${BKPR_DNS_ZONE}`, `https://kibana.${BKPR_DNS_ZONE}` and `https://grafana.${BKPR_DNS_ZONE}` respectively.

Congratulations! You can now deploy your applications on the Kubernetes cluster and BKPR will help you manage and monitor them effortlessly.

## Next steps

- [Installing Kubeapps on BKPR](kubeapps-on-bkpr.md)

## Upgrading

### Step 1: Update the installer

Follow the [installation guide](install.md) to update the BKPR installer binary to the latest release.

### Step 2: Edit `kubeprod-manifest.jsonnet`

Edit the `kubeprod-manifest.jsonnet` file that was generated by `kubeprod install` and update the version referred in the `import` statement. For example, the following snippet illustrates the changes required in the `kubeprod-manifest.jsonnet` file if you're upgrading to version `v1.1.0` from version `v1.0.0`.

```diff
 // Cluster-specific configuration
-(import "https://releases.kubeprod.io/files/v1.0.0/manifests/platforms/aks.jsonnet") {
+(import "https://releases.kubeprod.io/files/v1.1.0/manifests/platforms/aks.jsonnet") {
  config:: import "kubeprod-autogen.json",
  // Place your overrides here
 }
```

### Step 3: Perform the upgrade

Re-run the `kubeprod install` command, from the [Deploy BKPR](#step-2-deploy-bkpr) step, in the directory containing the existing `kubeprod-autogen.json` and updated `kubeprod-manifest.jsonnet` files.

## Teardown and cleanup

### Step 1: Uninstall BKPR from your cluster

  ```bash
  kubecfg delete kubeprod-manifest.jsonnet
  ```

### Step 2: Wait for the `kubeprod` namespace to be deleted

  ```bash
  kubectl wait --for=delete ns/kubeprod --timeout=300s
  ```

### Step 3: Delete the Azure DNS zone

  ```bash
  az network dns zone delete \
    --name ${BKPR_DNS_ZONE} \
    --resource-group ${AZURE_RESOURCE_GROUP}
  ```

  Additionally you should remove the NS entries configured at the domain registrar.

### Step 4: Delete Azure app registrations

  ```bash
  az ad app delete \
    --subscription ${AZURE_SUBSCRIPTION_ID} \
    --id $(jq -r .externalDns.aadClientId kubeprod-autogen.json)
  az ad app delete \
    --subscription ${AZURE_SUBSCRIPTION_ID} \
    --id $(jq -r .oauthProxy.client_id kubeprod-autogen.json)
  ```

### Step 5: Delete the AKS cluster

  ```bash
  az aks delete \
    --name ${AZURE_AKS_CLUSTER} \
    --resource-group ${AZURE_RESOURCE_GROUP}
  ```

### Step 6: Delete the Azure resource group

  ```bash
  az group delete --name ${AZURE_RESOURCE_GROUP}
  ```

## Further reading

- [BKPR FAQ](FAQ.md)
- [Troubleshooting](troubleshooting.md)
