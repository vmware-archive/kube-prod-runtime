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

local MARIADB_GALERA_IMAGE = (import "images.json")["mariadb-galera"];
local KEYCLOAK_IMAGE = (import "images.json").keycloak;

local KEYCLOAK_HTTP_PORT = 8080;
local KEYCLOAK_HTTPS_PORT = 8443;

local KEYCLOAK_DB_PORT = 3306;
local KEYCLOAK_DB_USER = "keycloak";
local KEYCLOAK_DB_DATABASE = "keycloak";

local KEYCLOAK_SCRIPTS_MOUNTPOINT = "/scripts";
local KEYCLOCK_CUSTOM_REALMS_MOUNTPOINT = "/realm/";
local KEYCLOAK_DEPLOYMENTS_MOUNTPOINT = "/opt/jboss/keycloak/standalone/deployments";

local KEYCLOAK_METRICS_PATH = "/auth/realms/master/metrics";

local bkpr_realm_json_tmpl = importstr "keycloak/bkpr_realm_json_tmpl";

{
  lib:: {
    kube: import "../lib/kube.libsonnet",
    utils: import "../lib/utils.libsonnet",
  },
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  galera: error "galera is required",
  oauth2_proxy: error "oauth2_proxy is required",

  serviceAccount: $.lib.kube.ServiceAccount($.p + "keycloak") + $.metadata {
  },

  secret: $.lib.utils.HashedSecret($.p + "keycloak") + $.metadata {
    local this = self,
    data_+: {
      "bkpr-realm.json": std.format(
        bkpr_realm_json_tmpl, [
          this.data_.client_id,
          this.data_.client_secret,
          "https://%s/oauth2/callback" % $.oauth2_proxy.ingress.host,
        ]
      ),
      client_id: error "client_id is required",
      client_secret: error "client_secret is required",
      admin_password: error "admin_password is required",
      db_password: error "db_password is required",
    },
  },

  scripts: $.lib.utils.HashedConfigMap($.p + "keycloak-sh") + $.metadata {
    data+: {
      "setup-db.sh": importstr "keycloak/setup-db.sh",
    },
  },

  sts: $.lib.kube.StatefulSet($.p + "keycloak") + $.metadata {
    local this = self,
    spec+: {
      podManagementPolicy: "Parallel",
      replicas: 1,
      updateStrategy: {type: "RollingUpdate"},
      template+: {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "%s" % KEYCLOAK_HTTP_PORT,
            "prometheus.io/path": KEYCLOAK_METRICS_PATH,
          },
        },
        spec+: {
          serviceAccountName: $.serviceAccount.metadata.name,
          // add AZ and node antiaffinity
          affinity+: $.lib.utils.weakNodeDiversity(this.spec.selector),
          default_container: "keycloak",
          securityContext: {
            fsGroup: 1001,
          },
          containers_+: {
            keycloak: $.lib.kube.Container("keycloak") {
              local container = self,
              image: KEYCLOAK_IMAGE,
              command: ["/opt/jboss/tools/docker-entrypoint.sh"],
              args+: [
                "-b=0.0.0.0",
                "-c=standalone.xml",
                "-Dkeycloak.import=/realm/bkpr-realm.json",
              ],
              securityContext: {
                runAsNonRoot: true,
                runAsUser: 1001,
              },
              resources: {
                requests: {cpu: "100m", memory: "1Gi"},
                limits: {
                  cpu: "1",
                  memory: "2Gi",
                },
              },
              ports_: {
                http: {containerPort: KEYCLOAK_HTTP_PORT},
                https: {containerPort: KEYCLOAK_HTTPS_PORT},
              },
              volumeMounts_+: {
                deployments: {
                  mountPath: KEYCLOAK_DEPLOYMENTS_MOUNTPOINT,
                },
                secret: {
                  mountPath: KEYCLOCK_CUSTOM_REALMS_MOUNTPOINT,
                  readOnly: true,
                },
              },
              env_+: {
                KEYCLOAK_USER: "admin",
                KEYCLOAK_PASSWORD: $.lib.kube.SecretKeyRef($.secret, "admin_password"),
                DB_VENDOR: "mariadb",
                DB_ADDR: $.galera.svc.host,
                DB_PORT: "3306",
                DB_USER: KEYCLOAK_DB_USER,
                DB_PASSWORD: $.lib.kube.SecretKeyRef($.secret, "db_password"),
                DB_DATABASE: KEYCLOAK_DB_DATABASE,
                PROXY_ADDRESS_FORWARDING: "true",
              },
              readinessProbe: {
                httpGet: {path: "/auth/realms/master", port: "http"},
                periodSeconds: 10,
                failureThreshold: 3,
                initialDelaySeconds: 30,
                successThreshold: 1,
              },
              livenessProbe: self.readinessProbe {
                httpGet: {path: "/auth/", port: "http"},
                initialDelaySeconds: 5 * 60,
                successThreshold: 1,
              },
            },
          },
          initContainers_+: {
            extensions: $.lib.kube.Container("extensions") {
              image: "busybox",
              command: ["sh", "-c", "wget -O /deployments/keycloak-metrics-spi.jar https://github.com/aerogear/keycloak-metrics-spi/releases/download/1.0.4/keycloak-metrics-spi-1.0.4.jar"],
              volumeMounts_+: {
                deployments: {
                  mountPath: "/deployments",
                },
              },
            },
            "setup-db": $.lib.kube.Container("setup-db") {
              image: MARIADB_GALERA_IMAGE,
              env_+: {
                KEYCLOAK_DB_HOST: $.galera.svc.host,
                KEYCLOAK_DB_PORT: "%s" % KEYCLOAK_DB_PORT,
                KEYCLOAK_DB_ROOT_USER: "root",
                KEYCLOAK_DB_ROOT_PASSWORD: $.lib.kube.SecretKeyRef($.galera.secret, "root_password"),
                KEYCLOAK_DB_USER: KEYCLOAK_DB_USER,
                KEYCLOAK_DB_PASSWORD: $.lib.kube.SecretKeyRef($.secret, "db_password"),
                KEYCLOAK_DB_DATABASE: KEYCLOAK_DB_DATABASE,
              },
              command: ["/scripts/setup-db.sh"],
              volumeMounts_+: {
                scripts: {
                  mountPath: KEYCLOAK_SCRIPTS_MOUNTPOINT,
                  readOnly: true,
                },
              },
            },
          },
          terminationGracePeriodSeconds: 60,
          volumes_+: {
            deployments: $.lib.kube.EmptyDirVolume(),
            scripts: $.lib.kube.ConfigMapVolume($.scripts) + {configMap+: {defaultMode: $.lib.kube.parseOctal("0755")}},
            secret: $.lib.kube.SecretVolume($.secret),
          },
        },
      },
    },
  },

  svc: $.lib.kube.Service($.p + "keycloak") + $.metadata {
    target_pod: $.sts.spec.template,
  },

  ingress: $.lib.utils.TlsIngress($.p + "keycloak") + $.metadata {
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
