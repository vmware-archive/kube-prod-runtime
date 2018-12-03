/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018 Bitnami
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
local utils = import "../lib/utils.libsonnet";

local GRAFANA_IMAGE = "bitnami/grafana:5.3.4-r6";

// TODO: add blackbox-exporter

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  // Default to "Editor".
  // User can create/modify dashboards & alert rules, but cannot create/edit
  // datasources nor invite new users
  auto_role:: "Editor",

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

  grafana: kube.StatefulSet($.p + "grafana") + $.metadata {
    spec+: {
      template+: {
        spec+: {
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
              },
              ports_+: {
                dashboard: { containerPort: 3000 },
              },
              volumeMounts_+: {
                datadir: { mountPath: "/var/lib/grafana" },
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
          storage: "1Gi",
        },
      },
    },
  },
}
