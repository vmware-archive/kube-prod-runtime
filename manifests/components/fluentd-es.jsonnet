local kube = import "kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "utils.libsonnet";

local FLUENTD_ES_IMAGE = "bitnami/fluentd:1.2.2-r22";
local FLUENTD_ES_CONFIGD_PATH = "/opt/bitnami/fluentd/conf/config.d";
local FLUENTD_ES_LOG_POS_PATH = "/var/log/fluentd-pos";
local FLUENTD_ES_LOG_BUFFERS_PATH = "/var/log/fluentd-buffers";

{
  p:: "",
  namespace:: { metadata+: { namespace: "kube-system" } },
  criticalPod:: { metadata+: { annotations+: { "scheduler.alpha.kubernetes.io/critical-pod": "" } } },
  config:: (import "fluentd-es-config.jsonnet"),

  es: error "elasticsearch is required",

  fluentd_es_config: kube.ConfigMap($.p + "fluentd-es") + $.namespace {
    data+: $.config,
  },

  serviceAccount: kube.ServiceAccount($.p + "fluentd-es") + $.namespace,

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

  daemonset: kube.DaemonSet($.p + "fluentd-es") + $.namespace {
    spec+: {
      template+: $.criticalPod {
        spec+: {
          initContainers_+: {
            // Required to have the proper permissions for the
            // $FLUENTD_ES_LOG_POS_PATH and $FLUENTD_ES_LOG_BUFFERS_PATH
            // directories
            fluentd_es_init: kube.Container("fluentd-es-init") {
              image: "alpine:3.6",
              command: [
                "/bin/chmod",
                "0775",
                FLUENTD_ES_LOG_POS_PATH,
                FLUENTD_ES_LOG_BUFFERS_PATH,
                ],
              securityContext: {
                privileged: true,
              },
              volumeMounts_+: {
                varlogpos: { mountPath: FLUENTD_ES_LOG_POS_PATH },
                varlogbuffers: { mountPath: FLUENTD_ES_LOG_BUFFERS_PATH },
              },
            },
          },
          containers_+: {
            fluentd_es: kube.Container("fluentd-es") {
              image: FLUENTD_ES_IMAGE,
              env_+: {
                FLUENTD_OPT: "-q",
                BUFFER_DIR: "/var/log/fluentd-buffers",
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
                configvolume: {
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
            configvolume: kube.ConfigMapVolume($.fluentd_es_config),
          },
        },
      },
    },
  },
}
