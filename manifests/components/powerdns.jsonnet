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

local MARIADB_GALERA_IMAGE = (import "images.json")["mariadb-galera"];

local POWERDNS_IMAGE = (import "images.json").powerdns;
local POWERDNS_DB_PORT = 3306;
local POWERDNS_DB_USER = "powerdns";
local POWERDNS_DB_DATABASE = "powerdns";

local POWERDNS_CONFIG_FILE = "/etc/pdns/pdns.conf";
local POWERDNS_SCRIPTS_MOUNTPOINT = "/scripts";

local POWERDNS_HTTP_PORT = 8081;
local POWERDNS_DNS_TCP_PORT = 53;
local POWERDNS_DNS_UDP_PORT = 53;

local pdns_conf_tpl = importstr "powerdns/pdns_conf_tpl";
local powerdns_sh_tpl = importstr "powerdns/powerdns_sh_tpl";

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  galera: error "galera is required",
  zone:: error "zone is required",

  scripts: utils.HashedConfigMap($.p + "powerdns-sh") + $.metadata {
    data+: {
      "powerdns.sh": std.format(powerdns_sh_tpl, [$.zone]),
      "setup-db.sh": importstr "powerdns/setup-db.sh",
    },
  },

  schema: utils.HashedConfigMap($.p + "powerdns") + $.metadata {
    data+: {
      "schema.sql": importstr "powerdns/schema.sql",
    },
  },

  secret: utils.HashedSecret($.p + "powerdns") + $.metadata {
    local this = self,
    data_+: {
      api_key: error "api_key is required",
      db_password: error "db_password is required",
      "pdns.conf": std.format(pdns_conf_tpl, [
        "%s" % POWERDNS_HTTP_PORT,
        $.galera.svc.host,
        "%s" % POWERDNS_DB_PORT,
        POWERDNS_DB_USER,
        this.data_.db_password,
        POWERDNS_DB_DATABASE,
      ]),
    },
  },

  deploy: kube.Deployment($.p + "powerdns") + $.metadata {
    local this = self,
    spec+: {
      replicas: 2,
      template+: {
        spec+: {
          containers_+: {
            kibana: kube.Container("pdns") {
              image: POWERDNS_IMAGE,
              command: ["/scripts/powerdns.sh"],
              args_+: {
                "api-key": "$(POWERDNS_API_KEY)",
                slave: "yes",
              },
              securityContext: {
                runAsUser: 0,
              },
              env_+: {
                POWERDNS_API_KEY: kube.SecretKeyRef($.secret, "api_key"),
              },
              ports_+: {
                api: {containerPort: POWERDNS_HTTP_PORT, protocol: "TCP"},
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
                scripts: {
                  mountPath: POWERDNS_SCRIPTS_MOUNTPOINT,
                  readOnly: true,
                },
                secret: {
                  mountPath: POWERDNS_CONFIG_FILE,
                  subPath: "pdns.conf",
                  readOnly: true,
                },
              },
            },
          },
          initContainers_+: {
            "setup-db": kube.Container("setup-db") {
              image: MARIADB_GALERA_IMAGE,
              env_+: {
                POWERDNS_DB_HOST: $.galera.svc.host,
                POWERDNS_DB_PORT: "%s" % POWERDNS_DB_PORT,
                POWERDNS_DB_ROOT_USER: "root",
                POWERDNS_DN_ROOT_PASSWORD: kube.SecretKeyRef($.galera.secret, "root_password"),
                POWERDNS_DB_USER: POWERDNS_DB_USER,
                POWERDNS_DB_PASSWORD: kube.SecretKeyRef($.secret, "db_password"),
                POWERDNS_DB_DATABASE: POWERDNS_DB_DATABASE,
              },
              command: ["/scripts/setup-db.sh"],
              volumeMounts_+: {
                schema: {
                  mountPath: "/schema/schema.sql",
                  subPath: "schema.sql",
                  readOnly: true,
                },
                scripts: {
                  mountPath: POWERDNS_SCRIPTS_MOUNTPOINT,
                  readOnly: true,
                },
              },
            },
          },
          volumes_+: {
            schema: kube.ConfigMapVolume($.schema),
            scripts: kube.ConfigMapVolume($.scripts) + {configMap+: {defaultMode: kube.parseOctal("0755")}},
            secret: kube.SecretVolume($.secret),
          },
        },
      },
    },
  },

  svc: kube.Service($.p + "powerdns") + $.metadata {
    target_pod: $.deploy.spec.template,
    spec+: {
      ports: [
        {name: "api", port: POWERDNS_HTTP_PORT, protocol: "TCP"},
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
