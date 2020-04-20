{
  // Allow overriding default lib and images (tags)
  lib:: error "lib must be set",
  images:: error "images must be set",
  // aux field to ease overriding each components' lib,images
  common:: {
    lib+:: $.lib,
    images+:: $.images,
  },
  cert_manager: (import "cert-manager.jsonnet") + $.common,
  edns: (import "externaldns.jsonnet") + $.common,
  nginx_ingress: (import "nginx-ingress.jsonnet") + $.common,
  prometheus: (import "prometheus.jsonnet") + $.common,
  oauth2_proxy: (import "oauth2-proxy.jsonnet") + $.common,
  fluentd_es: (import "fluentd-es.jsonnet") + $.common,
  elasticsearch: (import "elasticsearch.jsonnet") + $.common,
  kibana: (import "kibana.jsonnet") + $.common,
  grafana: (import "grafana.jsonnet") + $.common,
  pdns:: (import "powerdns.jsonnet") + $.common,
  galera:: (import "mariadb-galera.jsonnet") + $.common,
  keycloak:: (import "keycloak.jsonnet"),
}
