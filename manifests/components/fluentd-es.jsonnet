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

local FLUENTD_ES_IMAGE = (import "images.json")["fluentd"];
local FLUENTD_ES_CONF_PATH = "/opt/bitnami/fluentd/conf";
local FLUENTD_ES_CONFIGD_PATH = "/opt/bitnami/fluentd/conf/config.d";
local FLUENTD_ES_LOG_FILE = "/opt/bitnami/fluentd/logs/fluentd.log";
local FLUENTD_ES_LOG_POS_PATH = "/var/log/fluentd-pos";
local FLUENTD_ES_LOG_BUFFERS_PATH = "/var/log/fluentd-buffers";

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  criticalPod:: { metadata+: { annotations+: { "scheduler.alpha.kubernetes.io/critical-pod": "" } } },

  es: error "elasticsearch is required",

  fluentd_es_conf: kube.ConfigMap($.p + "fluentd-es") + $.metadata {
    data+: {
      "fluentd.conf": (importstr "fluentd-es-config/fluentd.conf"),
    },
  },

  fluentd_es_configd: kube.ConfigMap($.p + "fluentd-es-configd") + $.metadata {
    data+: {
      // Verbatim from upstream:
      "containers.input.conf": (importstr "fluentd-es-config/containers.input.conf"),
      "monitoring.conf": (importstr "fluentd-es-config/monitoring.conf"),
      "system.conf": (importstr "fluentd-es-config/system.conf"),
      "system.input.conf": (importstr "fluentd-es-config/system.input.conf"),
      // Edited to be templated via env vars
      "output.conf": (importstr "fluentd-es-config/output.conf"),
    },
  },

  serviceAccount: kube.ServiceAccount($.p + "fluentd-es") + $.metadata {
  },

  fluentdRole: kube.ClusterRole($.p + "fluentd-es") {
    rules: [
      {
        apiGroups: [""],
        resources: ["namespaces", "pods"],
        verbs: ["get", "watch", "list"],
      },
    ],
  },

  fluentdBinding: kube.ClusterRoleBinding($.p + "fluentd-es") {
    roleRef_: $.fluentdRole,
    subjects_+: [$.serviceAccount],
  },

  daemonset: kube.DaemonSet($.p + "fluentd-es") + $.metadata {
    spec+: {
      template+: $.criticalPod {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "24231",
            "prometheus.io/path": "/metrics",
          }
        },
        spec+: {
          containers_+: {
            fluentd_es: kube.Container("fluentd-es") {
              image: FLUENTD_ES_IMAGE,
              securityContext: {
                runAsUser: 0,  // required to be able to read system-wide logs.
              },
              env_+: {
                FLUENTD_OPT: "-o %s --log-rotate-age 5 --log-rotate-size 104857600 --no-supervisor" % FLUENTD_ES_LOG_FILE,
                ES_HOST: $.es.svc.host,
              },
              resources: {
                requests: { cpu: "100m", memory: "200Mi" },
                limits: { memory: "500Mi" },
              },
              volumeMounts_+: {
                varlog: {
                  mountPath: "/var/log",
                  readOnly: true,
                },
                varlogpos: { mountPath: FLUENTD_ES_LOG_POS_PATH },
                varlogbuffers: { mountPath: FLUENTD_ES_LOG_BUFFERS_PATH },
                varlibdockercontainers: {
                  mountPath: "/var/lib/docker/containers",
                  readOnly: true,
                },
                config: {
                  mountPath: FLUENTD_ES_CONF_PATH,
                  readOnly: true,
                },
                configd: {
                  mountPath: FLUENTD_ES_CONFIGD_PATH,
                  readOnly: true,
                },
              },
            },
          },
          // Note: from upstream, only for kube>=1.10?, may need to come from ../platforms
          // priorityClassName: "system-node-critical",
          serviceAccountName: $.serviceAccount.metadata.name,
          terminationGracePeriodSeconds: 30,
          volumes_+: {
            varlog: kube.HostPathVolume("/var/log", "Directory"),
            varlogpos: kube.HostPathVolume(FLUENTD_ES_LOG_POS_PATH, "DirectoryOrCreate"),
            varlogbuffers: kube.HostPathVolume(FLUENTD_ES_LOG_BUFFERS_PATH, "DirectoryOrCreate"),
            varlibdockercontainers: kube.HostPathVolume("/var/lib/docker/containers", "Directory"),
            config: kube.ConfigMapVolume($.fluentd_es_conf),
            configd: kube.ConfigMapVolume($.fluentd_es_configd),
          },
        },
      },
    },
  },
}
