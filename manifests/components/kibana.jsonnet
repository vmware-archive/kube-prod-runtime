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
local utils = import "../lib/utils.libsonnet";
local kubecfg = import "kubecfg.libsonnet";

local KIBANA_IMAGE = (import "images.json").kibana;
local KIBANA_PLUGINS_PATH = "/opt/bitnami/kibana/plugins";

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

  // List of Kibana plug-ins to install
  plugins:: {
    /* Example:
    logtrail: {
      version: "0.1.31",
      url: "https://github.com/sivasamyk/logtrail/releases/download/v0.1.31/logtrail-6.7.1-0.1.31.zip",
    },
    */
  },

  es: error "elasticsearch is required",

  serviceAccount: kube.ServiceAccount($.p + "kibana") + $.metadata {
  },

  pvc: kube.PersistentVolumeClaim($.p + "kibana-plugins") + $.metadata {
    storage: "2Gi",
  },

  deploy: kube.Deployment($.p + "kibana") + $.metadata {
    spec+: {
      template+: {
        spec+: {
          securityContext: {
            fsGroup: 1001,
          },
          volumes_+: {
            plugins: kube.PersistentVolumeClaimVolume($.pvc),
          },
          initContainers_+: {
            kibana_plugins_install: kube.Container("kibana-plugins-install") {
              image: KIBANA_IMAGE,
              securityContext: {
                allowPrivilegeEscalation: false,
              },
              local wanted = std.join("\n", ["%s@%s,%s" % [k, $.plugins[k].version, $.plugins[k].url] for k in std.objectFields($.plugins)]),
              command: [
                "/bin/sh",
                "-c",
                |||
                  set -e
                  rm -rf /opt/bitnami/kibana/plugins/lost+found
                  echo %s | sort > /tmp/wanted.list
                  /opt/bitnami/kibana/bin/kibana-plugin list | grep @ | sort > /tmp/installed.list
                  join -v2 -t, -j1 /tmp/wanted.list /tmp/installed.list | while read plugin; do
                    ${plugin:+/opt/bitnami/kibana/bin/kibana-plugin remove "${plugin%%@*}"}
                  done
                  join -v1 -t, -j1 -o1.2 /tmp/wanted.list /tmp/installed.list | while read url; do
                    ${url:+/opt/bitnami/kibana/bin/kibana-plugin install --no-optimize "$url"}
                  done
                ||| % std.escapeStringBash(wanted),
              ],
              volumeMounts_+: {
                // Persistence for Kibana plugins
                plugins: {
                  mountPath: KIBANA_PLUGINS_PATH,
                },
              },
            },
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
                  cpu: "1000m",  // initial startup requires lots of cpu
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
                ui: {containerPort: 5601},
              },
              volumeMounts_+: {
                // Persistence for Kibana plugins
                plugins: {
                  mountPath: KIBANA_PLUGINS_PATH,
                },
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
              {path: this.kibanaPath, backend: $.svc.name_port},
            ],
          },
        },
      ],
    },
  },
}
