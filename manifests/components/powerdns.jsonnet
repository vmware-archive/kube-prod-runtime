/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2020 Bitnami
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

local POWERDNS_IMAGE = (import "images.json").powerdns;

local POWERDNS_CONFIG_FILE = "/etc/pdns/pdns.conf";
local POWERDNS_DATA_MOUNTPOINT = "/var/lib/pdns";

local POWERDNS_API_PORT = 8081;
local POWERDNS_DNS_TCP_PORT = 53;
local POWERDNS_DNS_UDP_PORT = 53;

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  zone:: error "zone is required",
  api_key: error "api_key is required",

  config: utils.HashedConfigMap($.p + "powerdns") + $.metadata {
    data+: {
      "pdns.conf": importstr "powerdns/pdns.conf",
    },
  },

  schema: utils.HashedConfigMap($.p + "powerdns") + $.metadata {
    data+: {
      "schema.sql": importstr "powerdns/schema.sql",
    },
  },

  secret: utils.HashedSecret($.p + "powerdns") + $.metadata {
    data_+: {
      api_key: $.api_key,
    },
  },

  deploy: kube.Deployment($.p + "powerdns") + $.metadata {
    local this = self,
    spec+: {
      template+: {
        spec+: {
          securityContext: {
            fsGroup: 1001,
            runAsUser: 1001,
          },
          containers_+: {
            kibana: kube.Container("pdns") {
              image: POWERDNS_IMAGE,
              command: ["/usr/sbin/pdns_server"],
              args_+: {
                api: "true",
                "api-key": "$(POWERDNS_API_KEY)",
                webserver: "yes",
                "webserver-port": "%s" % POWERDNS_API_PORT,
                "webserver-address": "0.0.0.0",
                "webserver-allow-from": "0.0.0.0/0",
                slave: "yes",
                dnsupdate: "false",
              },
              securityContext: {
                runAsUser: 0,
              },
              env_+: {
                POWERDNS_API_KEY: kube.SecretKeyRef($.secret, "api_key"),
              },
              ports_+: {
                api: {containerPort: POWERDNS_API_PORT, protocol: "TCP"},
                "dns-tcp": {containerPort: POWERDNS_DNS_TCP_PORT, protocol: "TCP"},
                "dns-udp": {containerPort: POWERDNS_DNS_UDP_PORT, protocol: "UDP"},
              },
              readinessProbe: {
                httpGet: {path: "/", port: "api"},
              },
              livenessProbe: self.readinessProbe {
                httpGet: {path: "/", port: "api"},
              },
              volumeMounts_+: {
                data: {
                  mountPath: POWERDNS_DATA_MOUNTPOINT,
                },
                config: {
                  mountPath: POWERDNS_CONFIG_FILE,
                  subPath: "pdns.conf",
                  readOnly: true,
                },
              },
            },
          },
          initContainers_+: {
            "init-db": kube.Container("init-db") {
              image: POWERDNS_IMAGE,
              command: [
                "/bin/sh",
                "-c",
                |||
                  set -e
                  POWERDNS_SQLITE_DB=%s/pdns.db
                  if [ ! -f $POWERDNS_SQLITE_DB ]; then
                    cat /config/schema.sql | sqlite3 $POWERDNS_SQLITE_DB
                  fi
                  chmod 664 $POWERDNS_SQLITE_DB

                  ZONE=%s
                  if ! pdnsutil list-zone $ZONE; then
                    pdnsutil create-zone $ZONE ns1.$ZONE
                  fi
                ||| % [
                  POWERDNS_DATA_MOUNTPOINT,
                  $.zone,
                ],
              ],
              volumeMounts_+: {
                data: {
                  mountPath: POWERDNS_DATA_MOUNTPOINT,
                },
                config: {
                  mountPath: POWERDNS_CONFIG_FILE,
                  subPath: "pdns.conf",
                  readOnly: true,
                },
                schema: {
                  mountPath: "/config/schema.sql",
                  subPath: "schema.sql",
                  readOnly: true,
                },
              },
            },
          },
          volumes_+: {
            data: kube.EmptyDirVolume(),
            config: kube.ConfigMapVolume($.config),
            schema: kube.ConfigMapVolume($.schema),
          },
        },
      },
    },
  },

  svc: kube.Service($.p + "powerdns") + $.metadata {
    target_pod: $.deploy.spec.template,
    spec+: {
      ports: [
        {name: "api", port: POWERDNS_API_PORT, protocol: "TCP"},
        {name: "dns-tcp", port: POWERDNS_DNS_TCP_PORT, protocol: "TCP"},
        {name: "dns-udp", port: POWERDNS_DNS_UDP_PORT, protocol: "UDP"},
      ],
    },
  },

  ingress: utils.AuthIngress($.p + "powerdns") + $.metadata {
    local this = self,
    host:: error "host is required",
    spec+: {
      rules+: [
        {
          host: this.host,
          http: {
            paths: [
              {path: "/", backend: $.svc.name_port},
            ],
          },
        },
      ],
    },
  },
}
