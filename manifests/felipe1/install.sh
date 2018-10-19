#!/bin/bash
make -C ../../kubeprod || exit 1
../../kubeprod/bin/kubeprod install aks --platform=aks+k8s-1.9 --dns-resource-group felipe1 --dns-zone aks.azure.nami.run --email felipe@bitnami.com --manifests ../
kubectl -n kubeprod get pods --watch
