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

// NB: kubecfg is builtin
local kubecfg = import "kubecfg.libsonnet";

local PROMETHEUS_CONF_MOUNTPOINT = "/opt/bitnami/prometheus/conf/custom";
local PROMETHEUS_PORT = 9090;

local ALERTMANAGER_PORT = 9093;

// TODO: add blackbox-exporter

{
  lib:: {
    kube: import "../lib/kube.libsonnet",
    utils: import "../lib/utils.libsonnet",
    // Builds the `webhook-url` used by a container to trigger a reload
    // after a ConfigMap change
    get_cm_web_hook_url:: function(port, path) (
      local new_path = $.lib.utils.trimUrl(path);
      "http://localhost:%s%s/-/reload" % [port, new_path]
    ),
  },
  images:: import "images.json",

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

  retention_days:: 366 / 2,
  storage:: 1.5 * needed_space / 1e6,

  // Default monitoring rules
  basic_rules:: {
    K8sApiUnavailable: {
      expr: 'absent(up{job="kubernetes-apiservers"} == 1)',
      "for": "15m",
      labels: {severity: "critical"},
      annotations: {
        message: "Kubernetes API has disappeared from Prometheus target discovery",
      },
    },
    CrashLooping: {
      expr: "rate(kube_pod_container_status_restarts_total[15m]) * 60 * 5 > 0",
      "for": "1h",
      labels: {severity: "critical"},
      annotations: {
        message: "Pod {{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is restarting {{ $value }} times / 5 minutes.",
      },
    },
  },
  monitoring_rules:: {
    PrometheusBadConfig: {
      expr: 'max_over_time(prometheus_config_last_reload_successful{kubernetes_namespace="%s"}[5m]) == 0' % $.metadata.metadata.namespace,
      "for": "10m",
      labels: {severity: "critical"},
      annotations: {
        message: "Prometheus {{ $labels.namespace }}/{{ $labels.pod }} has failed to reload its configuration.",
      },
    },
    AlertmanagerBadConfig: {
      expr: 'alertmanager_config_last_reload_successful{kubernetes_namespace="%s"} == 0' % $.metadata.metadata.namespace,
      "for": "10m",
      labels: {severity: "warning"},
      annotations: {
        message: "Reloading Alertmanager's configuration has failed for {{ $labels.namespace }}/{{ $labels.pod }}.",
      },
    },
  },

  ingress: $.lib.utils.AuthIngress($.p + "prometheus") + $.metadata {
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
          rules: [{alert: kv[0]} + kv[1] for kv in $.lib.kube.objectItems($.basic_rules)],
        },
      ],
    },
    "basic.yaml": kubecfg.manifestYaml(self.basic_),
    monitoring_:: {
      groups: [
        {
          name: "monitoring.rules",
          rules: [{alert: kv[0]} + kv[1] for kv in $.lib.kube.objectItems($.monitoring_rules)],
        },
      ],
    },
    "monitoring.yml": kubecfg.manifestYaml(self.monitoring_),
  },

  prometheus: {
    local prom = self,

    serviceAccount: $.lib.kube.ServiceAccount($.p + "prometheus") + $.metadata {
    },

    prometheusRole: $.lib.kube.ClusterRole($.p + "prometheus") {
      rules: [
        {
          apiGroups: [""],
          resources: ["nodes", "nodes/proxy", "nodes/metrics", "services", "endpoints", "pods", "ingresses", "configmaps"],
          verbs: ["get", "list", "watch"],
        },
        {
          apiGroups: ["extensions"],
          resources: ["ingresses", "ingresses/status"],
          verbs: ["get", "list", "watch"],
        },
        {
          nonResourceURLs: ["/metrics"],
          verbs: ["get"],
        },
      ],
    },

    prometheusBinding: $.lib.kube.ClusterRoleBinding($.p + "prometheus") {
      roleRef_: prom.prometheusRole,
      subjects_+: [prom.serviceAccount],
    },

    svc: $.lib.kube.Service($.p + "prometheus") + $.metadata {
      target_pod: prom.deploy.spec.template,
    },

    config: $.lib.kube.ConfigMap($.p + "prometheus") + $.metadata {
      data+: $.rules {
        "prometheus.yml": kubecfg.manifestYaml($.config),
      },
    },

    deploy: $.lib.kube.StatefulSet($.p + "prometheus") + $.metadata {
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
              "prometheus.io/path": $.lib.utils.path_join($.ingress.prom_path, "metrics"),
            },
          },
          spec+: {
            terminationGracePeriodSeconds: 300,
            serviceAccountName: prom.serviceAccount.metadata.name,
            volumes_+: {
              config: $.lib.kube.ConfigMapVolume(prom.config),
            },
            securityContext+: {
              fsGroup: 1001,
            },
            containers_+: {
              default: $.lib.kube.Container("prometheus") {
                local this = self,
                image: $.images.prometheus,
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
              config_reload: $.lib.kube.Container("configmap-reload") {
                image: $.images["configmap-reload"],
                args_+: {
                  "volume-dir": "/config",
                  "webhook-url": $.lib.get_cm_web_hook_url(PROMETHEUS_PORT, $.ingress.prom_path),
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

    svc: $.lib.kube.Service($.p + "alertmanager") + $.metadata {
      target_pod: am.deploy.spec.template,
    },

    config: $.lib.kube.ConfigMap($.p + "alertmanager") + $.metadata {
      data+: {
        "config.yml": kubecfg.manifestYaml($.am_config),
      },
    },

    deploy: $.lib.kube.StatefulSet($.p + "alertmanager") + $.metadata {
      spec+: {
        volumeClaimTemplates_+: {
          storage: {storage: am.storage},
        },
        template+: {
          metadata+: {
            annotations+: {
              "prometheus.io/scrape": "true",
              "prometheus.io/port": std.toString(ALERTMANAGER_PORT),
              "prometheus.io/path": $.lib.utils.path_join($.ingress.am_path, "metrics"),
            },
          },
          spec+: {
            volumes_+: {
              config: $.lib.kube.ConfigMapVolume(am.config),
            },
            securityContext+: {
              runAsUser: 1001,
              fsGroup: 1001,
            },
            containers_+: {
              default: $.lib.kube.Container("alertmanager") {
                local this = self,
                image: $.images.alertmanager,
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
                  httpGet: {path: $.lib.utils.path_join($.ingress.am_path, "-/healthy"), port: ALERTMANAGER_PORT},
                  initialDelaySeconds: 60,
                  failureThreshold: 10,
                },
                readinessProbe+: self.livenessProbe {
                  initialDelaySeconds: 3,
                  timeoutSeconds: 3,
                  periodSeconds: 3,
                },
              },
              config_reload: $.lib.kube.Container("configmap-reload") {
                image: $.images["configmap-reload"],
                args_+: {
                  "volume-dir": "/config",
                  "webhook-url": $.lib.get_cm_web_hook_url(ALERTMANAGER_PORT, $.ingress.am_path),
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

  nodeExporter: {
    daemonset: $.lib.kube.DaemonSet($.p + "node-exporter") + $.metadata {
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
              root: $.lib.kube.HostPathVolume("/"),
              procfs: $.lib.kube.HostPathVolume("/proc"),
              sysfs: $.lib.kube.HostPathVolume("/sys"),
            },
            tolerations: [{
              effect: "NoSchedule",
              key: "node-role.kubernetes.io/master",
            }],
            containers_+: {
              default: $.lib.kube.Container("node-exporter") {
                image: $.images["node-exporter"],
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
    serviceAccount: $.lib.kube.ServiceAccount($.p + "kube-state-metrics") + $.metadata {
    },

    clusterRole: $.lib.kube.ClusterRole($.p + "kube-state-metrics") {
      local core = "",  // workaround empty-string-key bug in `jsonnet fmt`
      local listwatch = {
        [core]: ["configmaps", "endpoints", "limitranges", "namespaces", "nodes", "persistentvolumeclaims", "persistentvolumes", "pods", "replicationcontrollers", "resourcequotas", "secrets", "services"],
        "admissionregistration.k8s.io": ["mutatingwebhookconfigurations", "validatingwebhookconfigurations"],
        apps: ["daemonsets", "deployments", "replicasets", "statefulsets"],
        autoscaling: ["horizontalpodautoscalers"],
        "autoscaling.k8s.io": ["verticalpodautoscalers"],
        batch: ["cronjobs", "jobs"],
        "certificates.k8s.io": ["certificatesigningrequests"],
        extensions: ["daemonsets", "deployments", "ingresses", "replicasets"],
        "networking.k8s.io": ["ingresses", "networkpolicies"],
        policy: ["poddisruptionbudgets"],
        "storage.k8s.io": ["storageclasses", "volumeattachments"],
        "storageclasses.k8s.io": ["storageclasses"],
      },
      all_resources:: std.set(std.flattenArrays($.lib.kube.objectValues(listwatch))),
      rules: [{
        apiGroups: [k],
        resources: listwatch[k],
        verbs: ["list", "watch"],
      } for k in std.objectFields(listwatch)],
    },

    clusterRoleBinding: $.lib.kube.ClusterRoleBinding($.p + "kube-state-metrics") {
      roleRef_: $.ksm.clusterRole,
      subjects_: [$.ksm.serviceAccount],
    },

    role: $.lib.kube.Role($.p + "kube-state-metrics-resizer") + $.metadata {
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

    roleBinding: $.lib.kube.RoleBinding($.p + "kube-state-metrics") + $.metadata {
      roleRef_: $.ksm.role,
      subjects_: [$.ksm.serviceAccount],
    },

    deploy: $.lib.kube.Deployment($.p + "kube-state-metrics") + $.metadata {
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
              default+: $.lib.kube.Container("ksm") {
                image: $.images["kube-state-metrics"],
                ports_: {
                  metrics: {containerPort: 8080},
                },
                args_: {
                  collectors_:: std.set([
                    // "verticalpodautoscalers",
                    "certificatesigningrequests",
                    "configmaps",
                    "cronjobs",
                    "daemonsets",
                    "deployments",
                    "endpoints",
                    "horizontalpodautoscalers",
                    "ingresses",
                    "jobs",
                    "limitranges",
                    "mutatingwebhookconfigurations",
                    "namespaces",
                    "networkpolicies",
                    "nodes",
                    "persistentvolumeclaims",
                    "persistentvolumes",
                    "poddisruptionbudgets",
                    "pods",
                    "replicasets",
                    "replicationcontrollers",
                    "resourcequotas",
                    "secrets",
                    "services",
                    "statefulsets",
                    "storageclasses",
                    "validatingwebhookconfigurations",
                    "volumeattachments",
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
              resizer: $.lib.kube.Container("addon-resizer") {
                image: $.images["addon-resizer"],
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
                  MY_POD_NAME: $.lib.kube.FieldRef("metadata.name"),
                  MY_POD_NAMESPACE: $.lib.kube.FieldRef("metadata.namespace"),
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
