{
  // TODO(release): addon_resizer to use a single image
  addon_resizer:: {
    image:: "gcr.io/google_containers/addon-resizer:1.0",
  },
  addon_resizer__arch:: {
    image:: "gcr.io/google_containers/addon-resizer-%(arch)s:2.1",
  },
  alpine:: {
    image:: "alpine:3.6",
  },
  cert_manager:: {
    image:: "bitnami/cert-manager:0.5.0-r36",
  },
  configmap_reloader:: {
    image:: "jimmidyson/configmap-reload:v0.2.2",
  },
  default_backend:: {
    image:: "gcr.io/google_containers/defaultbackend:1.4",
  },
  elasticsearch:: {
    image:: "bitnami/elasticsearch:5.6.12-r2",
  },
  elasticsearch_exporter:: {
    image:: "justwatch/elasticsearch_exporter:1.0.1",
  },
  edns:: {
    image:: "bitnami/external-dns:0.5.4-r8",
  },
  etcd:: {
    image:: "quay.io/coreos/etcd:v3.3.1",
  },
  fluentd_es:: {
    image:: "bitnami/fluentd:1.2.2-r22",
  },
  gcp_broker:: {
    image:: "gcr.io/gcp-services/catalog-oauth:latest",  // FIXME: release?
  },
  heapster__arch:: {
    image:: "gcr.io/google_containers/heapster-%(arch)s:v1.5.2",
  },
  kibana:: {
    image:: "bitnami/kibana:5.6.12-r15",
  },
  nginx_ingress_controller:: {
    image:: "bitnami/nginx-ingress-controller:0.19.0-r8",
  },
  oauth2_proxy:: {
    image:: "bitnami/oauth2-proxy:0.20180625.74543-debian-9-r6",
  },
  prometheus:: {
    image:: "bitnami/prometheus:2.3.2-r41",
  },
  prometheus_node_exporter:: {
    image:: "prom/node-exporter:v0.15.2",
  },
  prometheus_alertmanager:: {
    image:: "bitnami/alertmanager:0.15.2-r36",
  },
  kube_state_metrics:: {
    image:: "quay.io/coreos/kube-state-metrics:v1.1.0",
  },
  kubernetes_svc_cat:: {
    image:: "quay.io/kubernetes-service-catalog/service-catalog:v0.1.9",
  },
}
