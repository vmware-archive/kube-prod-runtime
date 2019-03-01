# BKPR K8s Resource Policy

Version: 0.1

This document describes the standards and conventions used across our
Kubernetes resources.  It is intended primarily as an internal
reference, but may also be useful or interesting to other audiences.

## Generic Requirements

### Metadata

#### Labels

Labels are used as a per-namespace aggregation mechanism.  They need
to be unique to the set of resources being described.  As a minimum,
set the `name` label to the name (ie: `metadata.name`) of the
resource.

### NetworkPolicy

Must be declared and conservative, even if the underlying platform may
not actually enforce them (eg: minikube).

Specifically, no pod port may be accessible cluster-wide, and
clusterip services must only be accessible where they intend to
provide a cluster-wide service.

## Specific Resources

### PodSpec

#### Node Selectors

Must be set to the architectures supported by the docker image(s) used
in this pod.

#### Ports

Must be set to the list of ports intended to be exposed outside the
pod.  Note that Kubernetes treats this as informative only.

#### ServiceAccountName

Pods in the standard runtime must use an explicit ServiceAccount with
appropriately restricted permissions, *or* they must use
`automountServiceAccountToken: false` (and the `default` service
account).  Pods must not make API calls with the `default` service
account.

#### Liveness/Readiness Probes

All pods must specify a `livenessProbe`.  All pods that provide a
network service must specify a `readinessProbe`.

#### Mounts

Mounts of secrets, configMaps, downwardAPI, and projected volumes must
be explicitly mounted ReadOnly.  Other volumes should be mounted
read-only wherever possible.
