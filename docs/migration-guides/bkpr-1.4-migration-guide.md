# Migration Guide: Moving to BKPR v1.4

This document is for users who want to upgrade their Kubernetes clusters to BKPR v1.4.x from earlier BKPR releases.

## Requirements

* [Kubernetes cluster with BKPR v1.3.6](https://github.com/bitnami/kube-prod-runtime/releases/tag/v1.3.6)

## Overview

BKPR v1.4 support for Kubernetes 1.14 and 1.15 and update the BKPR in-cluster components to the latest major version releases. Before upgrading to this new release you need to perform some manual tasks in order for the upgrade process to complete successfully, namely:

1. [Backup Kibana index](#backup-kibana-index)
1. [Delete Kibana index](#delete-kibana-index)
1. [Delete ExternalDNS CRD](#delete-externaldns-crd)
1. [Upgrade to BKPR v1.4](#upgrade-to-bkpr-v14)
1. [Restore Kibana index](#restore-kibana-index)

## Backup Kibana index

The Kibana `6.7` index from BKPR `1.3` is not compatible with Kibana `7.5` installed in BKPR `1.4`. If you wish to retain the historical data you need to take a snapshot of the Kibana index.

Please refer to the official Elasticsearch docs in order to [Snapshot](https://www.elastic.co/guide/en/elasticsearch/reference/6.7/modules-snapshots.html) your Kibana index.

## Delete Kibana index

After you have your Kibana index backed up, you need to delete the Kibana index with the help of the `kubectl` command:

```bash
$ kubectl -n kubeprod exec -it elasticsearch-logging-0 -c elasticsearch-logging \
    curl -- -XDELETE http://localhost:9200/.kibana_1
```

## Delete ExternalDNS CRD

The `dnsendpoints.externaldns.k8s.io` CRDS has been updated in BKPR 1.4 and used a newer apiVersion. You need to manually delete this CRD.

```bash
$ kubectl delete crd dnsendpoints.externaldns.k8s.io
```

## Upgrade to BKPR v1.4

Follow the [BKPR upgrade instructions](../workflow.md#upgrading) to upgrade BKPR in your Kubernetes cluster.

## Restore Kibana index

If you generated a backup of the Kibana index, you can [restore](https://www.elastic.co/guide/en/elasticsearch/reference/6.7/modules-snapshots.html) it.

## Related Reading

- [Migration Guide: Moving to BKPR v1.3.6](bkpr-1.3.6-migration-guide.md)
- [Migration Guide: Moving to BKPR v1.2](bkpr-1.2-migration-guide.md)
