# BKPR Versioning 0.1

## Introduction

This document describes the versioning convention used in Bitnami Kubernetes Production Runtime (BKPR from now on) used by the binary and related Kubernetes manifests. It is based on [semantic versioning 2.0.0](https://semver.org).

## Summary

Given a version number MAJOR.MINOR.PATCH, increment the:

1. MAJOR version when you make incompatible API changes.
1. MINOR version when you add functionality in a backwards-compatible manner, and
1. PATCH version when you make backwards-compatible bug fixes.

BKPR consists of a series of Kubernetes manifests written in *jsonnet* and an accompanying binary named `kubeprod`.

## What triggers a version increment

* Security fixes will increment the PATCH version.
* Bug fixes, as long as the `kubeprod` binary and accompanying manifests are backwards compatible, will increment the MINOR version.
* Anything else will increment the MAJOR version.
