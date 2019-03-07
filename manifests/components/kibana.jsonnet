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

local KIBANA_IMAGE = (import "images.json")["kibana"];

local strip_trailing_slash(s) = (
  if std.endsWith(s, "/") then
    strip_trailing_slash(std.substr(s, 0, std.length(s) - 1))
  else
    s
);

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  es: error "elasticsearch is required",

  serviceAccount: kube.ServiceAccount($.p + "kibana") + $.metadata {
  },

  deploy: kube.Deployment($.p + "kibana") + $.metadata {
    spec+: {
      template+: {
        spec+: {
          securityContext: {
            fsGroup: 1001,
          },
          containers_+: {
            kibana: kube.Container("kibana") {
              image: KIBANA_IMAGE,
              securityContext: {
                runAsUser: 1001,
              },
              resources: {
                requests: {
                  cpu: "10m",
                },
                limits: {
                  cpu: "1000m", // initial startup requires lots of cpu
                },
              },
              env_+: {
                KIBANA_ELASTICSEARCH_URL: $.es.svc.host,
                SERVER_BASEPATH: strip_trailing_slash($.ingress.kibanaPath),
                KIBANA_HOST: "0.0.0.0",
                XPACK_MONITORING_ENABLED: "false",
                XPACK_SECURITY_ENABLED: "false",
              },
              ports_+: {
                ui: { containerPort: 5601 },
              },
            },
          },
        },
      },
    },
  },

  svc: kube.Service($.p + "kibana-logging") + $.metadata {
    target_pod: $.deploy.spec.template,
  },

  ingress: utils.AuthIngress($.p + "kibana-logging") + $.metadata {
    local this = self,
    host:: error "host is required",
    kibanaPath:: "/",
    spec+: {
      rules+: [
        {
          host: this.host,
          http: {
            paths: [
              { path: this.kibanaPath, backend: $.svc.name_port },
            ],
          },
        },
      ],
    },
  },
}
