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

local kube = import "../lib/kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "../lib/utils.libsonnet";

local GRAFANA_IMAGE = (import "images.json")["grafana"];
local GRAFANA_DATASOURCES_CONFIG = "/opt/bitnami/grafana/conf/provisioning/datasources";
local GRAFANA_DASHBOARDS_CONFIG = "/opt/bitnami/grafana/conf/provisioning/dashboards";
local GRAFANA_DATA_MOUNTPOINT = "/opt/bitnami/grafana/data";

// TODO: add blackbox-exporter

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  // Amount of persistent storage required by Alertmanager
  storage:: "1Gi",

  // List of plugins to install
  plugins:: [],

  prometheus:: error "No Prometheus service",

  // Default to "Admin". See http://docs.grafana.org/permissions/overview/ for
  // additional information.
  //
  // This effectively grants "Admin" to all Org user/ users (which are
  // authenticated by OAuth2 Proxy). An less secure alternative consists of
  // explicitly setting an Admin user by specifying its user name in the
  // GF_SECURITY_ADMIN_USER environment variable and its password in the
  // GF_SECURITY_ADMIN_PASSWORD environment variable, and setting `auto_role`
  // to "Editor".
  auto_role:: "Admin",

  svc: kube.Service($.p + "grafana") + $.metadata {
    target_pod: $.grafana.spec.template,
  },

  ingress: utils.AuthIngress($.p + "grafana") + $.metadata {
    local this = self,
    spec+: {
      rules+: [
        {
          host: this.host,
          http: {
            paths: [
              { path: "/", backend: $.svc.name_port },
            ],
          },
        },
      ],
    },
  },

  // Generates YAML configuration under provisioning/datasources/
  datasources: utils.HashedConfigMap($.p + "grafana-datasource-configuration") + $.metadata {
    local this = self,
    datasources:: {
      // Built-in datasource for BKPR's Prometheus
      "BKPR Prometheus": {
        type: "prometheus",
        access: "proxy",
        isDefault: true,
        url: $.prometheus.http_url,
      },
    },
    data+: {
      _config:: {
        apiVersion: 1,
        datasources: [{name: kv[0]} + kv[1] for kv in kube.objectItems(this.datasources)],
      },
      "bkpr.yml": kubecfg.manifestYaml(self._config),
    },
  },

  // Generates YAML dashboard configuration under provisioning/dashboards/
  dashboards_provider: utils.HashedConfigMap($.p + "grafana-dashboards-configuration") + $.metadata {
    local this = self,
    dashboard_provider:: {
      // Grafana dashboards configuration
      "kubernetes": {
        folder: "Kubernetes",
        type: "file",
        disableDeletion: false,
        editable: false,
        options: {
          path: utils.path_join(GRAFANA_DASHBOARDS_CONFIG, "kubernetes"),
        },
      },
    },
    data+: {
      _config:: {
        apiVersion: 1,
        providers: kube.mapToNamedList(this.dashboard_provider),
      },
      "dashboards_provider.yml": kubecfg.manifestYaml(self._config),
    },
  },

  kubernetes_dashboards: utils.HashedConfigMap($.p + "grafana-kubernetes-dashboards") + $.metadata {
    local this = self,
    data+: {
      "k8s_cluster_capacity.json": importstr "grafana-dashboards/handcrafted/kubernetes/k8s_cluster_capacity.json",
      "k8s_cluster_workloads_summary.json": importstr "grafana-dashboards/handcrafted/kubernetes/k8s_cluster_workloads_summary.json",
      "k8s_resource_usage_namespace_pods.json": importstr "grafana-dashboards/handcrafted/kubernetes/k8s_resource_usage_namespace_pods.json",
    },
  },

  grafana: kube.StatefulSet($.p + "grafana") + $.metadata {
    spec+: {
      template+: {
        spec+: {
          volumes_+: {
            datasources: kube.ConfigMapVolume($.datasources),
            dashboards_provider: kube.ConfigMapVolume($.dashboards_provider),
            kubernetes_dashboards: kube.ConfigMapVolume($.kubernetes_dashboards),
          },
          containers_+: {
            grafana: kube.Container("grafana") {
              image: GRAFANA_IMAGE,
              resources: {
                limits: { cpu: "100m", memory: "100Mi" },
                requests: self.limits,
              },
              env_+: {
                GF_AUTH_PROXY_ENABLED: "true",
                GF_AUTH_PROXY_HEADER_NAME: "X-Auth-Request-User",
                GF_AUTH_PROXY_HEADER_PROPERTY: "username",
                GF_AUTH_PROXY_HEADERS: "Email:X-Auth-Request-Email",
                GF_AUTH_PROXY_AUTO_SIGN_UP: "true",
                GF_SERVER_PROTOCOL: "http",
                GF_SERVER_DOMAIN: $.ingress.host,
                GF_SERVER_ROOT_URL: "https://" + $.ingress.host,
                GF_USERS_AUTO_ASSIGN_ORG_ROLE: $.auto_role,
                GF_USERS_AUTO_ASSIGN_ORG: "true",
                GF_USERS_ALLOW_SIGN_UP: "false",
                GF_EXPLORE_ENABLED: "true",
                GF_LOG_MODE: "console",
                GF_LOG_LEVEL: "warn",
                GF_METRICS_ENABLED: "true",
                GF_INSTALL_PLUGINS: std.join(",", $.plugins),
              },
              ports_+: {
                dashboard: { containerPort: 3000 },
              },
              volumeMounts_+: {
                datadir: { mountPath: GRAFANA_DATA_MOUNTPOINT },
                datasources: {
                  mountPath: utils.path_join(GRAFANA_DATASOURCES_CONFIG, "bkpr.yml"),
                  subPath: "bkpr.yml",
                  readOnly: true,
                },
                dashboards_provider: {
                  mountPath: utils.path_join(GRAFANA_DASHBOARDS_CONFIG, "dashboards_provider.yml"),
                  subPath: "dashboards_provider.yml",
                  readOnly: true,
                },
                kubernetes_dashboards: {
                  mountPath: utils.path_join(GRAFANA_DASHBOARDS_CONFIG, "kubernetes"),
                  readOnly: true,
                },
              },
              livenessProbe: self.readinessProbe {
                initialDelaySeconds: 60,
                successThreshold: 1,
              },
              readinessProbe: {
                tcpSocket: { port: "dashboard" },
                successThreshold: 2,
                initialDelaySeconds: 30,
              },
            },
          },
          securityContext: {
            // make pvc owned by this gid (Bitnami non-root gid)
            fsGroup: 1001,
          },
        },
      },
      volumeClaimTemplates_+: {
        datadir: {
          storage: $.storage,
        },
      },
    },
  },
}
