/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018-2019 Bitnami
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// See:
// https://github.com/prometheus/prometheus/blob/release-2.0/documentation/examples/prometheus-kubernetes.yml

local k8sScrape(role) = {
  kubernetes_sd_configs: [{role: role}],
  scheme: "https",
  tls_config: {
    ca_file: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt",
  },
  bearer_token_file: "/var/run/secrets/kubernetes.io/serviceaccount/token",
};

local NAMESPACE = "__meta_kubernetes_namespace";
local SERVICE_NAME = "__meta_kubernetes_service_name";
local ENDPOINT_PORT_NAME = "__meta_kubernetes_endpoint_port_name";
local NODE_NAME = "__meta_kubernetes_node_name";

{
  global: {
    scrape_interval_secs:: 60, // default
    scrape_interval: "%ds" % self.scrape_interval_secs,
    evaluation_interval: "60s", // default
  },

  alerting: {
    local a = self,
    am_namespace:: error "am_namespace is undefined",
    am_name:: "alertmanager",
    am_port:: "alertmanager",
    am_path:: "/",
    alertmanagers: [{
      path_prefix: a.am_path,
      kubernetes_sd_configs: [{role: "endpoints"}],
      relabel_configs: [{
        source_labels: [NAMESPACE, SERVICE_NAME, ENDPOINT_PORT_NAME],
        action: "keep",
        regex: std.join(";", [a.am_namespace, a.am_name, a.am_port]),
      }],
    }],
  },

  rule_files: [],

  scrape_configs_:: {
    prometheus: {
      static_configs: [{targets: ["localhost:9090"]}],
    },

    // Kubernetes exposes API servers as endpoints to the
    // default/kubernetes service so this uses `endpoints` role and
    // uses relabelling to only keep the endpoints associated with the
    // default/kubernetes service using the default named port
    // `https`. This works for single API server deployments as well
    // as HA API server deployments.
    apiservers: k8sScrape("endpoints") {
      job_name: "kubernetes-apiservers",
      // Keep only the default/kubernetes service endpoints for the
      // https port. This will add targets for each API server which
      // Kubernetes adds an endpoint to the default/kubernetes
      // service.
      relabel_configs: [
        {
          source_labels: [NAMESPACE, SERVICE_NAME, ENDPOINT_PORT_NAME],
          action: "keep",
          regex: "default;kubernetes;https",
        },
      ],
    },

    // Rather than connecting directly to the node, the scrape is
    // proxied though the Kubernetes apiserver.  This means it will
    // work if Prometheus is running out of cluster, or can't connect
    // to nodes for some other reason (e.g. because of firewalling).
    nodes: k8sScrape("node") {
      job_name: "kubernetes-nodes",
      relabel_configs: [
        {
          action: "labelmap",
          regex: "__meta_kubernetes_node_label_(.+)",
        },
        {
          target_label: "__address__",
          replacement: "kubernetes.default.svc:443",
        },
        {
          source_labels: [NODE_NAME],
          regex: "(.+)",
          target_label: "__metrics_path__",
          replacement: "/api/v1/nodes/${1}/proxy/metrics",
        },
      ],
    },

    // This is required for Kubernetes 1.7.3 and later, where cAdvisor
    // metrics (those whose names begin with 'container_') have been
    // removed from the Kubelet metrics endpoint.  This job scrapes
    // the cAdvisor endpoint to retrieve those metrics.
    //
    // In Kubernetes 1.7.0-1.7.2, these metrics are only exposed on the cAdvisor
    // HTTP endpoint; use "replacement: /api/v1/nodes/${1}:4194/proxy/metrics"
    // in that case (and ensure cAdvisor's HTTP server hasn't been disabled with
    // the --cadvisor-port=0 Kubelet flag).
    //
    // This job is not necessary and should be removed in Kubernetes
    // 1.6 and earlier versions, or it will cause the metrics to be
    // scraped twice.
    cadvisor: k8sScrape("node") {
      job_name: "kubernetes-cadvisor",
      relabel_configs: [
        {
          action: "labelmap",
          regex: "__meta_kubernetes_node_label_(.+)",
        },
        {
          target_label: "__address__",
          replacement: "kubernetes.default.svc:443",
        },
        {
          source_labels: [NODE_NAME],
          regex: "(.+)",
          target_label: "__metrics_path__",
          replacement: "/api/v1/nodes/${1}/proxy/metrics/cadvisor",
        },
      ],
    },

    service_endpoints: k8sScrape("endpoints") {
      job_name: "kubernetes-service-endpoints",
      scheme: "http",

      local ANNOTATION(key) = "__meta_kubernetes_service_annotation_prometheus_io_" + key,

      relabel_configs: [
        {
          source_labels: [ANNOTATION("scrape")],
          action: "keep",
          regex: true,
        },
        {
          source_labels: [ANNOTATION("scheme")],
          action: "replace",
          target_label: "__scheme__",
          regex: "(https?)",
        },
        {
          source_labels: [ANNOTATION("path")],
          action: "replace",
          target_label: "__metrics_path__",
          regex: "(.+)",
        },
        {
          source_labels: ["__address__", ANNOTATION("port")],
          action: "replace",
          target_label: "__address__",
          regex: "([^:]+)(?::\\d+)?;(\\d+)",
          replacement: "$1:$2",
        },
        {
          action: "labelmap",
          regex: "__meta_kubernetes_service_label_(.+)",
        },
        {
          source_labels: ["__meta_kubernetes_namespace"],
          action: "replace",
          target_label: "kubernetes_namespace",
        },
        {
          source_labels: ["__meta_kubernetes_service_name"],
          action: "replace",
          target_label: "kubernetes_name",
        },
      ],
    },

    // Example scrape config for probing services via the Blackbox Exporter.
    //
    // The relabeling allows the actual service scrape endpoint to be configured
    // via the following annotations:
    //
    // * `prometheus.io/probe`: Only probe services that have a value of `true`
    services: {
      job_name: "kubernetes-services",
      metrics_path: "/probe",
      params: {module: ["http_2xx"]},
      kubernetes_sd_configs: [{role: "service"}],

      local ANNOTATION(key) = "__meta_kubernetes_service_annotation_prometheus_io_" + key,

      relabel_configs: [
        {
          source_labels: [ANNOTATION("probe")],
          action: "keep",
          regex: true,
        },
        {
          source_labels: ["__address__"],
          target_label: "__param_target",
        },
        {
          target_label: "__address__",
          replacement: "blackbox-exporter:9115",
        },
        {
          source_labels: ["__param_target"],
          target_label: "instance",
        },
        {
          action: "labelmap",
          regex: "__meta_kubernetes_service_label_(.+)",
        },
        {
          source_labels: [NAMESPACE],
          target_label: "kubernetes_namespace",
        },
        {
          source_labels: [SERVICE_NAME],
          target_label: "kubernetes_name",
        },
      ],
    },

    ingresses: {
      job_name: "kubernetes-ingresses",
      metrics_path: "/probe",
      params: {module: ["http_2xx"]},
      kubernetes_sd_configs: [{role: "ingress"}],

      local ANNOTATION(key) = "__meta_kubernetes_ingress_annotation_prometheus_io_" + key,

      relabel_configs: [
        {
          source_labels: [ANNOTATION("probe")],
          action: "keep",
          regex: true,
        },
        {
          source_labels: [
            "__meta_kubernetes_ingress_scheme",
            "__address__",
            "__meta_kubernetes_ingress_path",
          ],
          regex: "(.+);(.+);(.+)",
          replacement: "${1}://${2}${3}",
          target_label: "__param_target",
        },
        {
          target_label: "__address__",
          replacement: "blackbox-exporter:9115",
        },
        {
          source_labels: ["__param_target"],
          target_label: "instance",
        },
        {
          action: "labelmap",
          regex: "__meta_kubernetes_ingress_label_(.+)",
        },
        {
          source_labels: ["__meta_kubernetes_namespace"],
          target_label: "kubernetes_namespace",
        },
        {
          source_labels: ["__meta_kubernetes_ingress_name"],
          target_label: "kubernetes_name",
        },
      ],
    },

    // Example scrape config for pods
    //
    // The relabeling allows the actual pod scrape endpoint to be
    // configured via the following annotations:
    //
    // * `prometheus.io/scrape`: Only scrape pods that have a value of `true`
    // * `prometheus.io/path`: If the metrics path is not `/metrics` override this.
    // * `prometheus.io/port`: Scrape the pod on the indicated port instead of the
    // pod's declared ports (default is a port-free target if none are declared).
    pods: {
      job_name: "kubernetes-pods",
      kubernetes_sd_configs: [{role: "pod"}],

      local ANNOTATION(key) = "__meta_kubernetes_pod_annotation_prometheus_io_" + key,

      relabel_configs: [
        {
          source_labels: [ANNOTATION("scrape")],
          action: "keep",
          regex: true,
        },
        {
          source_labels: [ANNOTATION("path")],
          action: "replace",
          target_label: "__metrics_path__",
          regex: "(.+)",
        },
        {
          source_labels: ["__address__", ANNOTATION("port")],
          action: "replace",
          regex: "([^:]+)(?::\\d+)?;(\\d+)",
          replacement: "$1:$2",
          target_label: "__address__",
        },
        {
          action: "labelmap",
          regex: "__meta_kubernetes_pod_label_(.+)",
        },
        {
          source_labels: ["__meta_kubernetes_namespace"],
          action: "replace",
          target_label: "kubernetes_namespace",
        },
        {
          source_labels: ["__meta_kubernetes_pod_name"],
          action: "replace",
          target_label: "kubernetes_pod_name",
        },
      ],
    },
  },
  scrape_configs: [{job_name: k} + self.scrape_configs_[k]
                   for k in std.objectFields(self.scrape_configs_)],
}
