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
local MARIADB_GALERA_DATA_MOUNTPOINT = "/bitnami/mariadb";
local MARIADB_GALERA_CONFIG_DIR = "/opt/bitnami/mariadb/conf";
local MARIADB_GALERA_MYSQL_PORT = 3306;
local MARIADB_GALERA_REPLICATION_PORT = 4567;
local MARIADB_GALERA_IST_PORT = 4568;
local MARIADB_GALERA_SST_PORT = 4444;

local MYSQLD_EXPORTER_IMAGE = (import "images.json")["mysqld-exporter"];
local MYSQLD_EXPORTER_PORT = 9104;

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  sa: kube.ServiceAccount($.p + "mariadb-galera") + $.metadata {
  },

  role: kube.Role($.p + "mariadb-galera") + $.metadata {
    rules: [
      {
        apiGroups: [""],
        resources: ["endpoints"],
        verbs: ["get"],
      },
    ],
  },

  roleBinding: kube.RoleBinding($.p + "mariadb-galera") + $.metadata {
    roleRef_: $.role,
    subjects_+: [$.sa],
  },

  config: utils.HashedConfigMap($.p + "mariadb-galera") + $.metadata {
    data+: {
      "my.cnf": (importstr "mariadb-galera/my.cnf"),
    },
  },

  secret: utils.HashedSecret($.p + "mariadb-galera") + $.metadata {
    data_+: {
      root_password: error "root_password is required",
      mariabackup_password: error "mariabackup_password is required",
    },
  },

  sts: kube.StatefulSet($.p + "mariadb-galera") + $.metadata {
    local this = self,
    spec+: {
      replicas: 3,
      updateStrategy: {type: "RollingUpdate"},
      template+: {
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          affinity: kube.PodZoneAntiAffinityAnnotation(this.spec.template),
          default_container: "mariadb-galera",
          volumes_+: {
            config: kube.ConfigMapVolume($.config),
          },
          securityContext: {
            fsGroup: 1001,
            runAsUser: 1001,
          },
          containers_+: {
            "mariadb-galera": kube.Container("mariadb-galera") {
              image: MARIADB_GALERA_IMAGE,
              env_+: {
                MARIADB_GALERA_CLUSTER_NAME: "galera",
                MARIADB_GALERA_CLUSTER_ADDRESS: "gcomm://%s" % $.headless.host,
                MARIADB_ROOT_PASSWORD: kube.SecretKeyRef($.secret, "root_password"),
                MARIADB_GALERA_MARIABACKUP_USER: "mariabackup",
                MARIADB_GALERA_MARIABACKUP_PASSWORD: kube.SecretKeyRef($.secret, "mariabackup_password"),
              },
              ports_+: {
                mysql: {containerPort: MARIADB_GALERA_MYSQL_PORT},
                galera: {containerPort: MARIADB_GALERA_REPLICATION_PORT},
                ist: {containerPort: MARIADB_GALERA_IST_PORT},
                sst: {containerPort: MARIADB_GALERA_SST_PORT},
              },
              volumeMounts_+: {
                data: {
                  mountPath: MARIADB_GALERA_DATA_MOUNTPOINT,
                },
                config: {
                  mountPath: "%s/my.cnf" % MARIADB_GALERA_CONFIG_DIR,
                  subPath: "my.cnf",
                  readOnly: true,
                },
              },
              readinessProbe: {
                exec: {
                  command: [
                    "/bin/bash",
                    "-ec",
                    |||
                      exec mysqladmin status -uroot -p$MARIADB_ROOT_PASSWORD
                    |||,
                  ],
                },
                initialDelaySeconds: 30,
                periodSeconds: 10,
                failureThreshold: 3,
                successThreshold: 1,
                timeoutSeconds: 1,
              },
              livenessProbe: self.readinessProbe {
                initialDelaySeconds: 2 * 60,
                successThreshold: 1,
              },
            },
            metrics: kube.Container("metrics") {
              image: MYSQLD_EXPORTER_IMAGE,
              command: [
                "sh",
                "-c",
                |||
                  DATA_SOURCE_NAME="root:$MARIADB_ROOT_PASSWORD@(localhost:%s)/" /bin/mysqld_exporter
                ||| % MARIADB_GALERA_MYSQL_PORT,
              ],
              env_+: {
                MARIADB_ROOT_PASSWORD: kube.SecretKeyRef($.secret, "root_password"),
              },
              ports_+: {
                metrics: {containerPort: MYSQLD_EXPORTER_PORT},
              },
              readinessProbe: {
                httpGet: {path: "/metrics", port: "metrics"},
                initialDelaySeconds: 5,
                timeoutSeconds: 1,
              },
              livenessProbe: self.readinessProbe {
                initialDelaySeconds: 30,
                timeoutSeconds: 5,
              },
              resources: {
                limits: {cpu: "100m", memory: "512Mi"},
                requests: self.limits,
              },
            },
          },
        },
      },
      volumeClaimTemplates_+: {
        data: {storage: "100Gi"},
      },
    },
  },

  svc: kube.Service($.p + "mariadb-galera") + $.metadata {
    target_pod: $.sts.spec.template,
    metadata+: {
      annotations+: {
        "prometheus.io/port": "%s" % MYSQLD_EXPORTER_PORT,
        "prometheus.io/scrape": "true",
      },
    },
    spec+: {
      ports: [
        {name: "mysql", port: MARIADB_GALERA_MYSQL_PORT, protocol: "TCP"},
        {name: "metrics", port: MYSQLD_EXPORTER_PORT, protocol: "TCP"},
      ],
    },
  },

  headless: kube.Service($.p + "mariadb-galera-headless") + $.metadata {
    target_pod: $.sts.spec.template,
    spec+: {
      clusterIP: "None",
      ports: [
        {name: "galera", port: MARIADB_GALERA_REPLICATION_PORT, protocol: "TCP"},
        {name: "ist", port: MARIADB_GALERA_IST_PORT, protocol: "TCP"},
        {name: "sst", port: MARIADB_GALERA_SST_PORT, protocol: "TCP"},
      ],
    },
  },
}
