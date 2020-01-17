# Migration Guide: Moving to BKPR v1.3.6

This document is for users who want to upgrade their Kubernetes clusters to BKPR v1.3.6 from earlier BKPR releases.

## Requirements

* Kubernetes cluster with BKPR <= v1.3.5

## Overview

BKPR 1.3.6 includes and emergency update of cert-manager 0.12.0 and requires that the CRDs are updates for this versions. We need to manually delete some cluster resources for the BKPR upgrade process to complete sucessfully.

## Delete cert-manager clusterissuers

```bash
kubectl delete clusterissuers.certmanager.k8s.io $(kubectl get clusterissuers.certmanager.k8s.io -o jsonpath="{.items[0:].metadata.name}")
```

## Delete cert-manager CustomResourceDefinitions

```bash
kubectl delete crds $(kubectl get crds -l kubecfg.ksonnet.io/garbage-collect-tag=kube_prod_runtime -o jsonpath="{.items[0:].metadata.name}")
```

## Upgrade to BKPR v1.3.6

Follow the [BKPR upgrade instructions](../workflow.md#upgrading) to upgrade BKPR in your Kubernetes cluster.

## Related Reading

- [Migration Guide: Moving to BKPR v1.2](bkpr-1.2-migration-guide.md)
