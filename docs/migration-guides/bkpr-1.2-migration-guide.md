# Migration Guide: Moving to BKPR v1.2

This document is for users who want to upgrade their Kubernetes clusters to BKPR v1.2 from BKPR v1.1. The document will assist in migrating a Kubernetes cluster to BKPR v1.2. Be sure to read this guide in its entirety before performing the upgrade.

## Requirements

* Kubernetes cluster with BKPR v1.1

## Overview

Making the move to BKPR v1.2 is a simple process that involves the following steps:

1. Migrate Kibana index to 6.0
1. Upgrade to BKPR v1.2

## Migrate Kibana index to 6.0

In BPKR v1.2, Elasticsearch and Kibana have been upgraded to version 6. Before upgrading to BKPR v1.2, your Kibana index needs to be reindexed in order to migrate to Kibana 6.

Changes will be made to your Kibana index, it is recommended that you [backup your Kibana index](https://www.elastic.co/guide/en/elasticsearch/reference/5.6/modules-snapshots.html) before proceeding.

The [official Kibana 6 index migration guide](https://www.elastic.co/guide/en/kibana/6.0/migrating-6.0-index.html#migrating-6.0-index) lists the steps to follow for migrating the Kibana index to the 6.0 format.

> **Note**:
>
> To perform the migration with zero downtime, add `"index.format": 6` and `"index.mapping.single_type": true` under `settings` in the second step of the Kibana index migration guide.

Access the Kibana console editor by visiting `https://kibana.my-domain.com/app/kibana#/dev_tools/console`* and execute the steps listed in the [Kibana index migration guide](https://www.elastic.co/guide/en/kibana/6.0/migrating-6.0-index.html#migrating-6.0-index).

_*Replace `my-domain.com` in the above URL with the DNS suffix specified while installing BKPR_

## Upgrade to BKPR v1.2

Follow the [BKPR upgrade instructions](../workflow.md#upgrading) to upgrade BKPR in your Kubernetes cluster to v1.2.

## Resources

* [Elasticsearch 6.0 Release Notes](https://www.elastic.co/guide/en/elasticsearch/reference/6.0/es-release-notes.html)
* [Elasticsearch 6.0 Breaking Changes](https://www.elastic.co/guide/en/elasticsearch/reference/6.0/breaking-changes-6.0.html)
* [Migrating Kibana index to 6.0](https://www.elastic.co/guide/en/kibana/6.0/migrating-6.0-index.html)
