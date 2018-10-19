#!/bin/bash
make -C ../../kubeprod || exit 1
../../kubeprod/bin/kubeprod install aks --platform=aks+k8s-1.9 --dns-resource-group felipe2 --dns-zone felipe.fuloi.org --email felipe@bitnami.com --manifests ../
kubectl -n kube-system get pods --watch
