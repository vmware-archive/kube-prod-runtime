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
local KEYCLOAK_HTTP_PORT = 80;
local KEYCLOAK_HTTPS_PORT = 443;

local KEYCLOAK_DATA_MOUNTPOINT = "/opt/jboss/keycloak/standalone/data";
local KEYCLOCK_CUSTOM_REALM_PATH = "/realm/";

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

  scripts: utils.HashedConfigMap($.p + "keycloak-sh") + $.metadata {
    data+: {
      "keycloak.sh": importstr "keycloak/keycloak.sh"
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
            "prometheus.io/path": "/auth/realms/master/metrics",
          },
        },
        spec+: {
          serviceAccountName: $.serviceAccount.metadata.name,
          affinity: kube.PodZoneAntiAffinityAnnotation(this.spec.template),
          default_container: "keycloak",
          securityContext: {
            fsGroup: 1000,
          },
          containers_+: {
            keycloak: kube.Container("keycloak") {
              local container = self,
              image: KEYCLOAK_IMAGE,
              command: ["/scripts/keycloak.sh"],
              securityContext: {
                runAsNonRoot: true,
                runAsUser: 1000
              },
              resources: {
                requests: {cpu: "100m", memory: "1Gi"},
                limits: {
                  cpu: "1",
                  memory: "2Gi",
                },
              },
              ports_: {
                http: {containerPort: 8080},
                https: {containerPort: 8443},
              },
              volumeMounts_+: {
                data: {
                  mountPath: KEYCLOAK_DATA_MOUNTPOINT
                },
                scripts: {
                  mountPath: "/scripts",
                  readOnly: true
                },
                secret: {
                  mountPath: KEYCLOCK_CUSTOM_REALM_PATH,
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
          terminationGracePeriodSeconds: 60,
          volumes_+: {
            secret: kube.SecretVolume($.secret),
            scripts: kube.ConfigMapVolume($.scripts) + {
              configMap+: {defaultMode: kube.parseOctal("0755")},
            },
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
    metadata+: {
      annotations: {
        // force LetsEncrypt production certificate for identity server
        "cert-manager.io/cluster-issuer": "letsencrypt-prod"
      },
    },
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
