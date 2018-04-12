#!/bin/sh

PLATFORM="$1"
installer="$2"

topdir=${0%/*}/../..

set -e -x

# Block until cluster is ready
while ! kubectl cluster-info; do sleep 3; done

$installer install -v --platform=$PLATFORM --manifests $topdir/manifests

cd $topdir/tests
exec ginkgo -p -- -kubeconfig "$KUBECONFIG"
