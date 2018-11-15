# Quickstart: BKPR on Google Kubernetes Engine (GKE)

## Introduction

This document walks you through setting up a Google Kubernetes Engine (GKE) cluster and installing the Bitnami Kubernetes Production Runtime (BKPR) on the cluster.

## Prerequisites

* [Google Cloud account](https://cloud.google.com/billing/docs/how-to/manage-billing-account)
* [Google Cloud SDK](https://cloud.google.com/sdk/)
* [Kubernetes CLI](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [BKPR installer](install.md)
* [kubecfg](https://github.com/ksonnet/kubecfg/releases)
* [jq](https://stedolan.github.io/jq/)

## Installation and setup

### Step 1: Set up the cluster

In this section, you will deploy a Google Kubernetes Engine (GKE) cluster using the `gcloud` CLI.

* Configure the following environment variables:

  ```bash
  export GCLOUD_USER="$(gcloud info --format='value(config.account)')"
  export GCLOUD_PROJECT="my-gce-project"
  export GCLOUD_REGION="us-east1-d"
  export GCLOUD_DNS_ZONE="my-domain.com"
  export GCLOUD_AUTHZ_DOMAIN="my-domain.com"
  export GCLOUD_K8S_CLUSTER="my-gke-cluster"
  export GCLOUD_K8S_VERSION="1.10"
  ```

  - `GCLOUD_USER` specifies the email address used in requests to Let's Encrypt.
  - `GCLOUD_PROJECT` specifies the Google Cloud project. `gcloud projects list` lists your Google Cloud projects.
  - `GCLOUD_REGION` specifies the Google Cloud region. `gcloud compute regions list` lists the available Google Cloud regions.
  - `GCLOUD_DNS_ZONE` specifies the DNS suffix for the externally-visible websites and services deployed in the cluster.
  - `GCLOUD_AUTHZ_DOMAIN` specifies the email domain of authorized users and needs to be a [G Suite](https://gsuite.google.com/) domain. Alternatively, you could specify the value `*`, but be __WARNED__ that this will authorize any Google account holder to authenticate with OAuth to your cluster services.
  - `GCLOUD_K8S_CLUSTER` specifies the name of the GKE cluster.
  - `GCLOUD_K8S_VERSION` specifies the version of Kubernetes to use for creating the cluster. The [BKPR Kubernetes version support matrix](../README.md#kubernetes-version-support-matrix-for-bkpr-10) lists the base Kubernetes versions supported by BKPR. `gcloud container get-server-config --project ${GCLOUD_PROJECT} --zone ${GCLOUD_REGION}` lists the versions available in your region.

* Create an OAuth Client ID by following these steps:

  1. Go to <https://console.developers.google.com/apis/credentials>.
  2. Select the project from the drop down menu.
  3. In the center pane, select the __OAuth consent screen__ tab.
  4. Enter a __Application name__ .
  5. Add the TLD of the domain specified in the `GCLOUD_DNS_ZONE` variable to the __Authorized domains__ and save the changes.
  6. Choose the __Credentials__ tab and select the __Create Credentials > OAuth client ID__ .
  7. Select the __Web application__ option and fill in a name.
  8. Finally, add the following redirect URIs and hit __Create__ .
      + https://prometheus.{GCLOUD_DNS_ZONE}/oauth2/callback.
      + https://kibana.{GCLOUD_DNS_ZONE}/oauth2/callback.

  > Replace `{GCLOUD_DNS_ZONE}` with the value of the `GCLOUD_DNS_ZONE` environment variable*

Specify the displayed OAuth client id and secret in the `GCLOUD_OAUTH_CLIENT_KEY` and `GCLOUD_OAUTH_CLIENT_SECRET` environment variables, for example:

  ```bash
  export GCLOUD_OAUTH_CLIENT_KEY="xxxxxxx.apps.googleusercontent.com"
  export GCLOUD_OAUTH_CLIENT_SECRET="xxxxxx"
  ```

9. Specify the OAuth Client id and secret in environment variables named `GCLOUD_OAUTH_CLIENT_KEY` and `GCLOUD_OAUTH_CLIENT_SECRET` respectively.


* Authenticate the `gcloud` CLI with your Google Cloud account:

  ```bash
  gcloud auth login
  ```

* Set the Google Cloud application default credentials:

  ```bash
  gcloud auth application-default login
  ```

* Set the default project:

  ```bash
  gcloud config set project ${GCLOUD_PROJECT}
  ```

* Set the default region:

  ```bash
  gcloud config set compute/zone ${GCLOUD_REGION}
  ```

* Create the GKE cluster:

  ```bash
  gcloud container clusters create ${GCLOUD_K8S_CLUSTER} \
    --project ${GCLOUD_PROJECT} \
    --num-nodes 3 \
    --machine-type n1-standard-2 \
    --zone ${GCLOUD_REGION} \
    --cluster-version ${GCLOUD_K8S_VERSION}
  ```

* Create a `cluster-admin` role binding:

  ```bash
  kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud info --format='value(config.account)')
  ```

### Step 2: Deploy BKPR

To bootstrap your Kubernetes cluster with BKPR:

  ```bash
  kubeprod install gke \
    --email "${GCLOUD_USER}" \
    --manifests "./bkpr-${BKPR_VERSION}/manifests" \
    --dns-zone "${GCLOUD_DNS_ZONE}" \
    --project "${GCLOUD_PROJECT}" \
    --oauth-client-id "${GCLOUD_OAUTH_CLIENT_KEY}" \
    --oauth-client-secret "${GCLOUD_OAUTH_CLIENT_SECRET}" \
    --authz-domain "${GCLOUD_AUTHZ_DOMAIN}"
  ```

Wait for all the pods in the cluster to enter `Running` state:

  ```bash
  kubectl get pods -n kubeprod
  ```

If you want to bootstrap the cluster from scratch after a failed run, you should remove `kubeprod-manifest.jsonnet` file.

#### Warning

The `kubeprod-autogen.json` file stores sensitive information. Do not commit this file in a GIT repository.

### Step 3: Configure domain registration records

BKPR creates and manages a Cloud DNS zone which is used to map external access to applications and services in the cluster. However, for it to be usable, you need to configure the NS records for the zone.

Query the name servers of the zone with the following command and configure the records with your domain registrar.

  ```bash
  GCLOUD_DNS_ZONE_NAME=$(gcloud dns managed-zones list --filter dnsName:${GCLOUD_DNS_ZONE} --format='value(name)')
  gcloud dns record-sets list \
    --zone ${GCLOUD_DNS_ZONE_NAME} \
    --name ${GCLOUD_DNS_ZONE} --type NS \
    --format=json | jq -r .[].rrdatas
  ```

Please note, it can take a while for the DNS changes to propogate.

### Step 4: Access logging and monitoring dashboards

After the DNS changes have propagated you should be able to access the Prometheus and Kibana dashboards by visiting `https://prometheus.${GCLOUD_DNS_ZONE}` and `https://kibana.${GCLOUD_DNS_ZONE}` respectively.

Congratulations! You can now deploy your applications on the Kubernetes cluster and BKPR will help you manage and monitor them effortlessly.

## Teardown and cleanup

### Step 1: Uninstall BKPR from your cluster

  ```bash
  kubecfg delete kubeprod-manifest.jsonnet
  ```

### Step 2: Delete the Cloud DNS zone

  ```bash
  GCLOUD_DNS_ZONE_NAME=$(gcloud dns managed-zones list --filter dnsName:${GCLOUD_DNS_ZONE} --format='value(name)')
  gcloud dns record-sets import /dev/null --zone ${GCLOUD_DNS_ZONE_NAME} --delete-all-existing
  gcloud dns managed-zones delete ${GCLOUD_DNS_ZONE_NAME}
  ```

### Step 3: Delete service account and IAM profile

  ```bash
  GCLOUD_SERVICE_ACCOUNT=$(gcloud iam service-accounts list --filter "displayName:${GCLOUD_DNS_ZONE} AND email:bkpr-edns" --format='value(email)')
  gcloud projects remove-iam-policy-binding ${GCLOUD_PROJECT} \
    --member=serviceAccount:${GCLOUD_SERVICE_ACCOUNT} \
    --role=roles/dns.admin
  gcloud iam service-accounts delete ${GCLOUD_SERVICE_ACCOUNT}
  ```

### Step 4: Delete the GKE cluster

  ```bash
  gcloud container clusters delete ${GCLOUD_K8S_CLUSTER}
  ```

### Step 5: Delete any leftover GCE disks

  ```bash
  GCLOUD_DISKS_FILTER=${GCLOUD_K8S_CLUSTER:0:18}
  gcloud compute disks delete --zone ${GCLOUD_DNS_ZONE} \
    $(gcloud compute disks list --filter name:${GCLOUD_DISKS_FILTER%-} --format='value(name)') \
  ```
