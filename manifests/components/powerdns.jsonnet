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

// NB: kubecfg is builtin
local kubecfg = import "kubecfg.libsonnet";

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
  lib:: {
    kube: import "../lib/kube.libsonnet",
    utils: import "../lib/utils.libsonnet",
  },
  images:: import "images.json",

  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  galera: error "galera is required",
  zone:: error "zone is required",

  scripts: $.lib.utils.HashedConfigMap($.p + "powerdns-sh") + $.metadata {
    data+: {
      "powerdns.sh": std.format(powerdns_sh_tpl, [$.zone]),
      "setup-db.sh": importstr "powerdns/setup-db.sh",
    },
  },

  schema: $.lib.utils.HashedConfigMap($.p + "powerdns") + $.metadata {
    data+: {
      "schema.sql": importstr "powerdns/schema.sql",
    },
  },

  secret: $.lib.utils.HashedSecret($.p + "powerdns") + $.metadata {
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

  deploy: $.lib.kube.Deployment($.p + "powerdns") + $.metadata {
    local this = self,
    spec+: {
      replicas: 2,
      template+: {
        spec+: {
          containers_+: {
            kibana: $.lib.kube.Container("pdns") {
              image: $.images.powerdns,
              command: ["/scripts/powerdns.sh"],
              args_+: {
                "api-key": "$(POWERDNS_API_KEY)",
                slave: "yes",
              },
              securityContext: {
                runAsUser: 0,
              },
              env_+: {
                POWERDNS_API_KEY: $.lib.kube.SecretKeyRef($.secret, "api_key"),
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
            "setup-db": $.lib.kube.Container("setup-db") {
              image: $.images["mariadb-galera"],
              env_+: {
                POWERDNS_DB_HOST: $.galera.svc.host,
                POWERDNS_DB_PORT: "%s" % POWERDNS_DB_PORT,
                POWERDNS_DB_ROOT_USER: "root",
                POWERDNS_DN_ROOT_PASSWORD: $.lib.kube.SecretKeyRef($.galera.secret, "root_password"),
                POWERDNS_DB_USER: POWERDNS_DB_USER,
                POWERDNS_DB_PASSWORD: $.lib.kube.SecretKeyRef($.secret, "db_password"),
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
            schema: $.lib.kube.ConfigMapVolume($.schema),
            scripts: $.lib.kube.ConfigMapVolume($.scripts) + {configMap+: {defaultMode: $.lib.kube.parseOctal("0755")}},
            secret: $.lib.kube.SecretVolume($.secret),
          },
        },
      },
    },
  },

  svc: $.lib.kube.Service($.p + "powerdns") + $.metadata {
    target_pod: $.deploy.spec.template,
    spec+: {
      ports: [
        {name: "api", port: POWERDNS_HTTP_PORT, protocol: "TCP"},
        {name: "dns-tcp", port: POWERDNS_DNS_TCP_PORT, protocol: "TCP"},
        {name: "dns-udp", port: POWERDNS_DNS_UDP_PORT, protocol: "UDP"},
      ],
    },
  },

  ingress: $.lib.utils.AuthIngress($.p + "powerdns") + $.metadata {
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
