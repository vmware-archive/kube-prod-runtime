#!/bin/bash
helm install stable/wordpress \
  --name blog \
  --set serviceType=ClusterIP \
  --set ingress.enabled=true \
  --set ingress.hosts[0].name=blog.felipe.fuloi.org \
  --set ingress.hosts[0].tls=true \
  --set ingress.hosts[0].tlsSecret=blog-tls \
  --set ingress.hosts[0].annotations.kubernetes\\.io/tls-acme=true --debug
