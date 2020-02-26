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

local KEYCLOAK_IMAGE = (import "images.json").keycloak;
local KEYCLOAK_HTTP_PORT = 8080;
local KEYCLOAK_HTTPS_PORT = 8443;

local KEYCLOCK_CUSTOM_REALMS_MOUNTPOINT = "/realm/";
local KEYCLOAK_DATA_MOUNTPOINT = "/opt/jboss/keycloak/standalone/data";
local KEYCLOAK_DEPLOYMENTS_MOUNTPOINT = "/opt/jboss/keycloak/standalone/deployments";

local KEYCLOAK_METRICS_PATH = "/auth/realms/master/metrics";

local bkpr_realm_json_tmpl = importstr "keycloak/bkpr_realm_json_tmpl";

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  client_id: error "client_id is required",
  client_secret: error "client_secret is required",
  admin_password: error "admin_password is required",

  oauth2_proxy: error "oauth2_proxy is required",

  serviceAccount: kube.ServiceAccount($.p + "keycloak") + $.metadata {
  },

  secret: utils.HashedSecret($.p + "keycloak") + $.metadata {
    data_+: {
      "bkpr-realm.json": std.format(bkpr_realm_json_tmpl, [
          $.client_id,
          $.client_secret,
          "https://%s/oauth2/callback" % $.oauth2_proxy.ingress.host
        ]
      ),
      admin_password: $.admin_password,
    },
  },

  sts: kube.StatefulSet($.p + "keycloak") + $.metadata {
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
          affinity: kube.PodZoneAntiAffinityAnnotation(this.spec.template),
          default_container: "keycloak",
          securityContext: {
            fsGroup: 1001,
          },
          containers_+: {
            keycloak: kube.Container("keycloak") {
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
                runAsUser: 1001
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
                data: {
                  mountPath: KEYCLOAK_DATA_MOUNTPOINT
                },
                deployments: {
                  mountPath: KEYCLOAK_DEPLOYMENTS_MOUNTPOINT,
                },
                secret: {
                  mountPath: KEYCLOCK_CUSTOM_REALMS_MOUNTPOINT,
                  readOnly: true
                },
              },
              env_+: {
                KEYCLOAK_USER: "admin",
                KEYCLOAK_PASSWORD: kube.SecretKeyRef($.secret, "admin_password"),
                // TODO: use a proper database for keycloak
                DB_VENDOR: "h2",
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
            extensions: kube.Container("extensions") {
              image: "busybox",
              command: ["sh", "-c", "wget -O /deployments/keycloak-metrics-spi.jar https://github.com/aerogear/keycloak-metrics-spi/releases/download/1.0.4/keycloak-metrics-spi-1.0.4.jar"],
              volumeMounts_+: {
                deployments: {
                  mountPath: "/deployments"
                },
              },
            },
          },
          terminationGracePeriodSeconds: 60,
          volumes_+: {
            deployments: kube.EmptyDirVolume(),
            secret: kube.SecretVolume($.secret),
          },
        },
      },
      volumeClaimTemplates_+: {
        data: {storage: "10Gi"},
      },
    },
  },

  svc: kube.Service($.p + "keycloak") + $.metadata {
    target_pod: $.sts.spec.template,
  },

  ingress: utils.TlsIngress($.p + "keycloak") + $.metadata {
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
