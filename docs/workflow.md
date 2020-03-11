
# Workflows

This document describes two different yet common workflows in BKPR using `kubeprod` and `kubecfg`:

* [Basic workflow](#basic-workflow)
* [Advanced workflow](#advanced-workflow)

These workflows are intended for users of BKPR, most likely developers, DevOps, Kubernetes operators, etc.

* The basic workflow covers those cases where the person using BKPR owns the Kubernetes cluster and has full privileges on it. This is usually the case for end-users who want to experiment with BKPR or developers working on a Kubernetes cluster on which they have full administrative privileges.
* The advanced workflow is intended for operators of production Kubernetes clusters which require greater customization and tuning that is not supported by the basic workflow.

## Pre-requisites

* [Kubernetes cluster](../readme.md#kubernetes-version-support-matrix)
* [`kubeprod`](https://github.com/bitnami/kube-prod-runtime/releases) binary
* [`kubecfg`](https://github.com/ksonnet/kubecfg/releases) binary

## Basic workflow

Use the basic workflow if you are:

* An end-user or developer with full administrative privileges to a Kubernetes cluster.
* An operator for a Kubernetes cluster that does not already have existing DNS and authentication infrastructure already in place.

The basic workflow is covered in the quickstart guides:

- [Quickstart: BKPR on Azure Kubernetes Service (AKS)](quickstart-aks.md)
- [Quickstart: BKPR on Google Kubernetes Engine (GKE)](quickstart-gke.md)
- [Quickstart: BKPR on Amazon Elastic Container Service for Kubernetes (EKS)](quickstart-eks.md)
- [Quickstart: BKPR on Generic Kubernetes Cluster (experimental)](quickstart-generic.md)

## Advanced workflow

The advanced workflow allows for greater control and customization than the basic workflow but involves several steps to get BKPR deployed to an existing Kubernetes cluster.

Use the advanced workflow if you are:

* An operator for a Kubernetes cluster that has existing DNS or authentication infrastructure already in place.
* Concerned with other cases where the basic workflow is not suitable.

We will use `kubeprod` and `kubecfg` to manage the BKPR lifecycle. `kubeprod` is part of BKPR and [`kubecfg`](https://github.com/ksonnet/kubecfg) is a tool for managing Kubernetes resources as code. `kubecfg` uses [jsonnet](https://jsonnet.org) to describe infrastructure based on templates. `kubeprod` is used to deploy BKPR into an existing Kubernetes cluster and `kubecfg` is used to show the differences between the running (live) configuration and the local configuration (e.g. your Git client).

### Check the default `kubectl` context

Ensure your default context in the Kubernetes `kubectl` client is the expected one:

```bash
kubectl config current-context
kubectl cluster-info
```

### Prepare the cluster

This step prepares the Kubernetes cluster and the underlying platform for deploying BKPR. This is accomplished by using `kubeprod install <platform>` where `<platform>` is the underlying platform for the Kubernetes cluster (e.g. AKS or GKE).

For example:

```bash
kubeprod install gke --only-generate \
                     --dns-zone ${dnsZone} \
                     --email ${email} \
                     --authz-domain ${authzDomain} \
                     --project ${gceProject} \
                     --oauth-client-id ${oauthClientId} \
                     --oauth-client-secret ${oauthClientSecret}
```

The `--only-generate` command-line flag tells `kubeprod` to configure the underlying platform (in this example, GKE) by creating the DNS zone if necessary, service accounts, etc. Afterwards, the root manifest and JSON configuration files are generated and `kubeprod` exits cleanly. At this point the operator can inspect the changes introduced by `kubeprod` and perform any customizations as explained next.

### Implement customizations (optional)

Please, check [the documentation about customizations](overrides.md).

### Test changes (only if BKPR is already deployed)

For example, to show the differences between the live state (what is currently running in the Kubernetes cluster) and the local configuration reflects, you can use `kubecfg diff` on the root manifest, like this:

```bash
kubecfg diff kubeprod-manifest.jsonnet
```

### Deploy changes

```bash
kubecfg update --ignore-unknown=true --gc-tag kube_prod_runtime kubeprod-manifest.jsonnet
```

The `kube_prod_runtime` garbage collection tag specified in the `kubecfg update` command takes care of garbage collection to ensure there is no leakage of Kubernetes resources.

> **NOTE**
> A [bug in kubecfg](https://github.com/ksonnet/kubecfg/issues/211) requires that the `--ignore-unknown=true` flag always be specified.

### Upgrading

The instructions provided here are the generic upgrade steps. Before you perform the upgrade please read the release notes for any additional steps you may need to take before or after performing an upgrade.

### Step 1: Update the installer

Follow the [installation guide](install.md) to update the BKPR installer binary to the latest release.

### Step 2: Edit `kubeprod-manifest.jsonnet`

The `kubeprod-manifest.jsonnet` file, generated by the `kubeprod install` command, imports BKPR jsonnet manifests and allows you to customize the BKPR configuration.

Edit the `kubeprod-manifest.jsonnet` file and update the `import` statement to point to manifests from the downloaded BKPR release.

### Step 3: Perform the upgrade

Change to the directory containing the existing `kubeprod-autogen.json` and updated `kubeprod-manifest.jsonnet` files and re-run the `kubeprod install` command to upgrade the BKPR cluster components.

### Check-in changes

For example,

```bash
git add kubeprod-manifest.jsonnet
git commit -m "Use Let's Encrypt staging environment"
```

Note that the **`kubeprod-autogen.json` file contains sensitive information**, like OAuth2 client and cookies secrets, or credentials for accessing the underlying platform's DNS services. If this information is inadvertently exposed, **it could compromise your Kubernetes cluster or any shared infrastructure**. As a best practice, we recommend explicitly ignoring kubeprod-autogen.json file in your source repository.
