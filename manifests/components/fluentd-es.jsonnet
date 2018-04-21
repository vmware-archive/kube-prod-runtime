local kube = import "kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "utils.libsonnet";

local FLUENTD_ES_IMAGE = "k8s.gcr.io/fluentd-elasticsearch:v2.0.4";

{
  p:: "",
  namespace:: { metadata+: { namespace: "kube-system" } },
  criticalPod:: { metadata+: { annotations+: { "scheduler.alpha.kubernetes.io/critical-pod": "" } } },
  config:: (import "fluentd-es-config.jsonnet"),

  fluentd_es_config: kube.ConfigMap($.p + "fluentd-es") + $.namespace {
    data+: $.config,
  },
  fluentd_es: {
    local f = self,
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
      roleRef_: f.fluentdRole,
      subjects_+: [f.serviceAccount],
    },
    daemonset: kube.DaemonSet($.p + "fluentd-es") + $.namespace {
      spec+: {
        template+: $.criticalPod {
          spec+: {
            containers_+: {
              fluentd_es: kube.Container("fluentd-es") {
                image: FLUENTD_ES_IMAGE,
                env_+: {
                  FLUENTD_ARGS: "--no-supervisor -q",
                  // TODO: As this uses node's /var/log/ for fluentd
                  // pos and (possibly large) buffer files, consider
                  // using instead emptydir or dynamically provisioned
                  // local dir (requires localdir provisioner, kube >=
                  // 1.10)
                  BUFFER_DIR: "/var/log/fluentd-buffers",
                  ES_HOST: $.p + "elasticsearch-logging",
                },
                resources: {
                  requests: { cpu: "100m", memory: "200Mi" },
                  limits: { memory: "500Mi" },
                },
                volumeMounts_+: {
                  // See TODO note at fluentd-es-config/output.conf re: voiding
                  // fluentd from using node's /var/log for buffering
                  varlog: { mountPath: "/var/log" },
                  varlibdockercontainers: {
                    mountPath: "/var/lib/docker/containers",
                    readOnly: true,
                  },
                  configvolume: {
                    mountPath: "/etc/fluent/config.d",
                  },
                },
              },
            },
            // Note: present in upstream to originally to cope with fluentd-es migration to DS, not applicable here
            // nodeSelector: {
            //  "beta.kubernetes.io/fluentd-ds-ready": "true",
            // },
            //
            // Note: from upstream, only for kube>=1.10?, may need to come from ../platforms
            // priorityClassName: "system-node-critical",
            serviceAccountName: f.serviceAccount.metadata.name,
            terminationGracePeriodSeconds: 30,
            volumes_+: {
              varlog: kube.HostPathVolume("/var/log"),
              varlibdockercontainers: kube.HostPathVolume("/var/lib/docker/containers"),
              configvolume: kube.ConfigMapVolume($.fluentd_es_config),
            },
          },
        },
      },
    },
  },
}
