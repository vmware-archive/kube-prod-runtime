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

local PROMETHEUS_IMAGE = (import "images.json")["prometheus"];
local PROMETHEUS_CONF_MOUNTPOINT = "/opt/bitnami/prometheus/conf/custom";
local PROMETHEUS_PORT = 9090;

local ALERTMANAGER_IMAGE = (import "images.json")["alertmanager"];
local ALERTMANAGER_PORT = 9093;

local CONFIGMAP_RELOAD_IMAGE = (import "images.json")["configmap-reload"];

// Builds the `webhook-url` used by a container to trigger a reload
// after a ConfigMap change
local get_cm_web_hook_url = function(port, path) (
  local new_path = utils.trimUrl(path);
  "http://localhost:%s%s/-/reload" % [port, new_path]
);

// TODO: add blackbox-exporter

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  // https://prometheus.io/docs/prometheus/2.0/storage/#operational-aspects
  //  On average, Prometheus uses only around 1-2 bytes per sample. Thus, to
  // plan the capacity of a Prometheus server, you can use the rough formula:
  //  needed_disk_space = retention_seconds * ingested_samples_per_second * bytes_per_sample
  local time_series = 10000,
  local bytes_per_sample = 2,
  local retention_seconds = self.retention_days * 86400,
  local ingested_samples_per_second = time_series / $.config.global.scrape_interval_secs,
  local needed_space = retention_seconds * ingested_samples_per_second * bytes_per_sample,

  retention_days:: 366/2,
  storage:: 1.5 * needed_space / 1e6,

  # Default monitoring rules
  basic_rules:: {
    K8sApiUnavailable: {
      expr: "max(up{job=\"kubernetes_apiservers\"}) != 1",
      "for": "10m",
      annotations: {
        summary: "Kubernetes API is unavailable",
        description: "Kubernetes API is not responding",
      },
    },
    CrashLooping: {
      expr: "sum(rate(kube_pod_container_status_restarts[15m])) BY (namespace, container) * 3600 > 0",
      "for": "1h",
      labels: {severity: "notice"},
      annotations: {
        summary: "Frequently restarting container",
        description: "{{$labels.namespace}}/{{$labels.container}} is restarting {{$value}} times per hour",
      },
    },
  },
  monitoring_rules:: {
    PrometheusBadConfig: {
      expr: "prometheus_config_last_reload_successful{kubernetes_namespace=\"%s\"} == 0" % $.metadata.metadata.namespace,
      "for": "10m",
      labels: {severity: "critical"},
      annotations: {
        summary: "Prometheus failed to reload config",
        description: "Config error with prometheus, see container logs",
      },
    },
    AlertmanagerBadConfig: {
      expr: "alertmanager_config_last_reload_successful{kubernetes_namespace=\"%s\"} == 0" % $.metadata.metadata.namespace,
      "for": "10m",
      labels: {severity: "critical"},
      annotations: {
        summary: "Alertmanager failed to reload config",
        description: "Config error with alertmanager, see container logs",
      },
    },
  },

  ingress: utils.AuthIngress($.p + "prometheus") + $.metadata {
    local this = self,
    host:: error "host is required",
    prom_path:: "/",
    am_path:: "/alertmanager",
    prom_url:: "http://%s%s" % [this.host, self.prom_path],
    am_url:: "http://%s%s" % [this.host, self.am_path],
    spec+: {
      rules+: [
        {
          host: this.host,
          http: {
            paths: [
              {path: this.prom_path, backend: $.prometheus.svc.name_port},
              {path: this.am_path, backend: $.alertmanager.svc.name_port},
            ],
          },
        },
      ],
    },
  },

  config:: (import "prometheus-config.jsonnet") {
    alerting+: {
      am_namespace: $.alertmanager.svc.metadata.namespace,
      am_name: $.alertmanager.svc.metadata.name,
      am_port: std.toString($.alertmanager.svc.spec.ports[0].name),
      am_path: $.ingress.am_path,
    },
    rule_files+: std.objectFields($.rules),
  },
  rules:: {
    // See also: https://github.com/coreos/prometheus-operator/tree/master/contrib/kube-prometheus/assets/prometheus/rules
    // "foo.yml": {...},
    basic_:: {
      groups: [
        {
          name: "basic.rules",
          rules: [{alert: kv[0]} + kv[1] for kv in kube.objectItems($.basic_rules)],
        },
      ],
    },
    "basic.yaml": kubecfg.manifestYaml(self.basic_),
    monitoring_:: {
      groups: [
        {
          name: "monitoring.rules",
          rules: [{alert: kv[0]} + kv[1], for kv in kube.objectItems($.monitoring_rules)],
        },
      ],
    },
    "monitoring.yml": kubecfg.manifestYaml(self.monitoring_),
  },

  prometheus: {
    local prom = self,

    serviceAccount: kube.ServiceAccount($.p + "prometheus") + $.metadata {
    },

    prometheusRole: kube.ClusterRole($.p + "prometheus") {
      rules: [
        {
          apiGroups: [""],
          resources: ["nodes", "nodes/proxy", "services", "endpoints", "pods"],
          verbs: ["get", "list", "watch"],
        },
        {
          apiGroups: ["extensions"],
          resources: ["ingresses"],
          verbs: ["get", "list", "watch"],
        },
        {
          nonResourceURLs: ["/metrics"],
          verbs: ["get"],
        },
      ],
    },

    prometheusBinding: kube.ClusterRoleBinding($.p + "prometheus") {
      roleRef_: prom.prometheusRole,
      subjects_+: [prom.serviceAccount],
    },

    svc: kube.Service($.p + "prometheus") + $.metadata {
      target_pod: prom.deploy.spec.template,
    },

    config: kube.ConfigMap($.p + "prometheus") + $.metadata {
      data+: $.rules {
        "prometheus.yml": kubecfg.manifestYaml($.config),
      },
    },

    deploy: kube.StatefulSet($.p + "prometheus") + $.metadata {
      spec+: {
        volumeClaimTemplates_: {
          data: {
            storage: "%dMi" % $.storage,
          },
        },
        template+: {
          metadata+: {
            annotations+: {
              "prometheus.io/scrape": "true",
              "prometheus.io/port": std.toString(PROMETHEUS_PORT),
              "prometheus.io/path": utils.path_join($.ingress.prom_path, "metrics"),
            },
          },
          spec+: {
            terminationGracePeriodSeconds: 300,
            serviceAccountName: prom.serviceAccount.metadata.name,
            volumes_+: {
              config: kube.ConfigMapVolume(prom.config),
            },
            securityContext+: {
              fsGroup: 1001,
            },
            containers_+: {
              default: kube.Container("prometheus") {
                local this = self,
                image: PROMETHEUS_IMAGE,
                securityContext+: {
                  runAsUser: 1001,
                },
                args_+: {
                  //"log.level": "debug",  // default is info

                  "web.external-url": $.ingress.prom_url,

                  "config.file": this.volumeMounts_.config.mountPath + "/prometheus.yml",
                  "storage.tsdb.retention.time": "%dd" % $.retention_days,

                  // These are unmodified upstream console files. May
                  // want to ship in config instead.
                  "web.console.libraries": "/opt/bitnami/prometheus/conf/console_libraries",
                  "web.console.templates": "/opt/bitnami/prometheus/conf/consoles",
                },
                args+: [
                  // Enable /-/reload hook.  TODO: move to SIGHUP when
                  // shared pid namespaces are widely supported.
                  "--web.enable-lifecycle",
                ],
                ports_+: {
                  web: {containerPort: PROMETHEUS_PORT},
                },
                volumeMounts_+: {
                  config: {mountPath: PROMETHEUS_CONF_MOUNTPOINT, readOnly: true},
                  data: {mountPath: "/opt/bitnami/prometheus/data"},
                },
                resources: {
                  requests: {cpu: "500m", memory: "500Mi"},
                },
                livenessProbe: self.readinessProbe {
                  httpGet: {path: "/", port: this.ports[0].name},
                  // Crash recovery can take a _long_ time (many
                  // minutes), depending on the time since last
                  // successful compaction.
                  initialDelaySeconds: 20 * 60,  // I have seen >10mins
                  successThreshold: 1,
                },
                readinessProbe: {
                  httpGet: {path: "/", port: this.ports[0].name},
                  successThreshold: 2,
                  initialDelaySeconds: 5,
                },
              },
              config_reload: kube.Container("configmap-reload") {
                image: CONFIGMAP_RELOAD_IMAGE,
                args_+: {
                  "volume-dir": "/config",
                  "webhook-url": get_cm_web_hook_url(PROMETHEUS_PORT, $.ingress.prom_path),
                  "webhook-method": "POST",
                },
                volumeMounts_+: {
                  config: {mountPath: "/config", readOnly: true},
                },
              },
            },
          },
        },
      },
    },
  },

  am_config:: (import "alertmanager-config.jsonnet"),

  alertmanager: {
    local am = self,

    // Amount of persistent storage required by Alertmanager
    storage:: "5Gi",

    svc: kube.Service($.p + "alertmanager") + $.metadata {
      target_pod: am.deploy.spec.template,
    },

    config: kube.ConfigMap($.p + "alertmanager") + $.metadata {
      data+: {
        "config.yml": kubecfg.manifestYaml($.am_config),
      },
    },

    deploy: kube.StatefulSet($.p + "alertmanager") + $.metadata {
      spec+: {
        volumeClaimTemplates_+: {
          storage: {storage: am.storage},
        },
        template+: {
          metadata+: {
            annotations+: {
              "prometheus.io/scrape": "true",
              "prometheus.io/port": std.toString(ALERTMANAGER_PORT),
              "prometheus.io/path": utils.path_join($.ingress.am_path, "metrics"),
            },
          },
          spec+: {
            volumes_+: {
              config: kube.ConfigMapVolume(am.config),
            },
            securityContext+: {
              runAsUser: 1001,
              fsGroup: 1001,
            },
            containers_+: {
              default: kube.Container("alertmanager") {
                local this = self,
                image: ALERTMANAGER_IMAGE,
                args_+: {
                  "config.file": this.volumeMounts_.config.mountPath + "/config.yml",
                  "storage.path": this.volumeMounts_.storage.mountPath,
                  "web.external-url": $.ingress.am_url,
                },
                ports_+: {
                  alertmanager: {containerPort: ALERTMANAGER_PORT},
                },
                volumeMounts_+: {
                  config: {mountPath: "/opt/bitnami/alertmanager/conf", readOnly: true},
                  storage: {mountPath: "/opt/bitnami/alertmanager/data"},
                },
                livenessProbe+: {
                  httpGet: {path: utils.path_join($.ingress.am_path, "-/healthy"), port: ALERTMANAGER_PORT},
                  initialDelaySeconds: 60,
                  failureThreshold: 10,
                },
                readinessProbe+: self.livenessProbe {
                  initialDelaySeconds: 3,
                  timeoutSeconds: 3,
                  periodSeconds: 3,
                },
              },
              config_reload: kube.Container("configmap-reload") {
                image: CONFIGMAP_RELOAD_IMAGE,
                args_+: {
                  "volume-dir": "/config",
                  "webhook-url": get_cm_web_hook_url(ALERTMANAGER_PORT, $.ingress.am_path),
                  "webhook-method": "POST",
                },
                volumeMounts_+: {
                  config: { mountPath: "/config", readOnly: true },
                },
              },
            },
          },
        },
      },
    },
  },

  nodeExporter: {
    daemonset: kube.DaemonSet($.p + "node-exporter") + $.metadata {
      local this = self,
      spec+: {
        template+: {
          metadata+: {
            annotations+: {
              "prometheus.io/scrape": "true",
              "prometheus.io/port": "9100",
              "prometheus.io/path": "/metrics",
            },
          },
          spec+: {
            hostNetwork: true,
            hostPID: true,
            volumes_+: {
              root: kube.HostPathVolume("/"),
              procfs: kube.HostPathVolume("/proc"),
              sysfs: kube.HostPathVolume("/sys"),
            },
            tolerations: [{
              effect: "NoSchedule",
              key: "node-role.kubernetes.io/master",
            }],
            containers_+: {
              default: kube.Container("node-exporter") {
                image: "bitnami/node-exporter:0.17.0-r1",
                local v = self.volumeMounts_,
                args_+: {
                  "path.procfs": v.procfs.mountPath,
                  "path.sysfs": v.sysfs.mountPath,

                  "collector.filesystem.ignored-mount-points":
                  "^(/rootfs|/host)?/(sys|proc|dev|host|etc)($|/)",

                  "collector.filesystem.ignored-fs-types":
                  "^(sys|proc|auto|cgroup|devpts|ns|au|fuse\\.lxc|mqueue)(fs)?$",
                },
                /* fixme
                args+: [
                  "collector."+c
                  for c in ["nfs", "mountstats", "systemd"]],
                */
                ports_+: {
                  scrape: {containerPort: 9100},
                },
                livenessProbe: {
                  httpGet: {path: "/", port: "scrape"},
                },
                readinessProbe: self.livenessProbe {
                  successThreshold: 2,
                },
                volumeMounts_+: {
                  root: {mountPath: "/rootfs", readOnly: true},
                  procfs: {mountPath: "/host/proc", readOnly: true},
                  sysfs: {mountPath: "/host/sys", readOnly: true},
                },
              },
            },
          },
        },
      },
    },
  },

  ksm: {
    serviceAccount: kube.ServiceAccount($.p + "kube-state-metrics") + $.metadata {
    },

    clusterRole: kube.ClusterRole($.p + "kube-state-metrics") {
      local listwatch = {
        "": ["nodes", "pods", "services", "resourcequotas", "replicationcontrollers", "limitranges", "persistentvolumeclaims", "namespaces"],
        extensions: ["daemonsets", "deployments", "replicasets"],
        apps: ["statefulsets"],
        batch: ["cronjobs", "jobs"],
      },
      all_resources:: std.set(std.flattenArrays(kube.objectValues(listwatch))),
      rules: [{
        apiGroups: [k],
        resources: listwatch[k],
        verbs: ["list", "watch"],
      } for k in std.objectFields(listwatch)],
    },

    clusterRoleBinding: kube.ClusterRoleBinding($.p + "kube-state-metrics") {
      roleRef_: $.ksm.clusterRole,
      subjects_: [$.ksm.serviceAccount],
    },

    role: kube.Role($.p + "kube-state-metrics-resizer") + $.metadata {
      rules: [
        {
          apiGroups: [""],
          resources: ["pods"],
          verbs: ["get"],
        },
        {
          apiGroups: ["extensions"],
          resources: ["deployments"],
          resourceNames: ["kube-state-metrics"],
          verbs: ["get", "update"],
        },
      ],
    },

    roleBinding: kube.RoleBinding($.p + "kube-state-metrics") + $.metadata {
      roleRef_: $.ksm.role,
      subjects_: [$.ksm.serviceAccount],
    },

    deploy: kube.Deployment($.p + "kube-state-metrics") + $.metadata {
      local deploy = self,
      spec+: {
        template+: {
          metadata+: {
            annotations+: {
              "prometheus.io/scrape": "true",
              "prometheus.io/port": "8080",
            },
          },
          spec+: {
            local spec = self,
            serviceAccountName: $.ksm.serviceAccount.metadata.name,
            containers_+: {
              default+: kube.Container("ksm") {
                image: "quay.io/coreos/kube-state-metrics:v1.1.0",
                ports_: {
                  metrics: {containerPort: 8080},
                },
                args_: {
                  collectors_:: std.set([
                    // remove "cronjobs" for kubernetes/kube-state-metrics#295
                    "daemonsets", "deployments", "limitranges", "nodes", "pods", "replicasets", "replicationcontrollers", "resourcequotas", "services", "jobs", "statefulsets", "persistentvolumeclaims",
                  ]),
                  collectors: std.join(",", self.collectors_),
                },
                local no_access = std.setDiff(self.args_.collectors_, $.ksm.clusterRole.all_resources),
                assert std.length(no_access) == 0 : "Missing clusterRole access for resources %s" % no_access,
                readinessProbe: {
                  httpGet: {path: "/healthz", port: 8080},
                  initialDelaySeconds: 5,
                  timeoutSeconds: 5,
                },
              },
              resizer: kube.Container("addon-resizer") {
                image: "k8s.gcr.io/addon-resizer:1.8.4",
                command: ["/pod_nanny"],
                args_+: {
                  container: spec.containers[0].name,
                  cpu: "100m",
                  "extra-cpu": "1m",
                  memory: "100Mi",
                  "extra-memory": "2Mi",
                  threshold: 5,
                  deployment: deploy.metadata.name,
                },
                env_+: {
                  MY_POD_NAME: kube.FieldRef("metadata.name"),
                  MY_POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
                },
                resources: {
                  limits: {cpu: "100m", memory: "30Mi"},
                  requests: self.limits,
                },
              },
            },
          },
        },
      },
    },
  },
}
