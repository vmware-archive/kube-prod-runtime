local kube = import "kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "utils.libsonnet";

local ELASTICSEARCH_IMAGE = "k8s.gcr.io/elasticsearch:v5.6.4";

{
  p:: "",
  namespace:: { metadata+: { namespace: "kube-system" } },
  elasticsearch: {
    local es = self,
    // NOTE: ES resources below tighten to be able to run these beasts in a 3x
    // AKS cluster with default VM resources
    resources:: { cpu: 100, memory: 1200, disk: 100 },

    serviceAccount: kube.ServiceAccount($.p + "elasticsearch") + $.namespace,

    elasticsearchRole: kube.ClusterRole($.p + "elasticsearch-logging") {
      rules: [
        {
          apiGroups: [""],
          resources: ["services", "namespaces", "endpoints"],
          verbs: ["get"],
        },
      ],
    },

    elasticsearchBinding: kube.ClusterRoleBinding($.p + "elasticsearch-logging") {
      roleRef_: es.elasticsearchRole,
      subjects_+: [es.serviceAccount],
    },

    sts: kube.StatefulSet($.p + "elasticsearch-logging") + $.namespace {
      spec+: {
        replicas: 3,
        template+: {
          metadata+: {
            annotations+: {
              "prometheus.io/scrape": "true",
              "prometheus.io/port": "9102",
            },
          },
          spec+: {
            default_container: "elasticsearch",
            containers_+: {
              elasticsearch: kube.Container("elasticsearch") {
                image: ELASTICSEARCH_IMAGE,
                // This can massively vary depending on the logging volume
                resources: {
                  requests: {
                    cpu: es.resources.cpu + "m",
                    memory: es.resources.memory + "Mi",
                  },
                  limits: {
                    cpu: (2 * es.resources.cpu) + "m",
                    memory: (2 * es.resources.memory) + "Mi",
                  },
                },
                ports_+: {
                  db: { containerPort: 9200 },
                  transport: { containerPort: 9300 },
                },
                volumeMounts_+: {
                  datadir: { mountPath: "/data" },
                },
                env_+: {
                  // These two below are used by elasticsearch_logging_discovery
                  NAMESPACE: kube.FieldRef("metadata.namespace"),
                  ELASTICSEARCH_SERVICE_NAME: es.svc.metadata.name,

                  // Verify quorum requirements
                  min_master_nodes:: 2,
                  assert (es.sts.spec.replicas >= self.min_master_nodes &&
                          es.sts.spec.replicas < self.min_master_nodes * 2) :
                         "Not enough quorum, verify min_master_nodes vs replicas",
                  MINIMUM_MASTER_NODES: std.toString(self.min_master_nodes),
                  ES_JAVA_OPTS: std.join(" ", [
                    "-XX:+UnlockExperimentalVMOptions",
                    "-XX:+UseCGroupMemoryLimitForHeap",
                    "-XX:MaxRAMFraction=1",
                  ]),
                },
                readinessProbe: {
                  httpGet: { path: "/_cluster/health?local=true", port: "db" },
                  // don't allow rolling updates to kill containers until the cluster is green
                  // ...meaning it's not allocating replicas or relocating any shards
                  initialDelaySeconds: 2 * 60,
                  periodSeconds: 30,
                  failureThreshold: 4,

                },
                livenessProbe: self.readinessProbe {
                  // elasticsearch_logging_discovery has a 5min timeout on cluster bootstrap
                  initialDelaySeconds: 5 * 60,
                },
              },
              prom_exporter: kube.Container("prom-exporter") {
                image: "justwatch/elasticsearch_exporter:1.0.1",
                command: ["elasticsearch_exporter"],
                args_+: {
                  "es.uri": "http://localhost:9200/",
                  "es.all": "false",
                  "es.timeout": "20s",
                  "web.listen-address": ":9102",
                  "web.telemetry-path": "/metrics",
                },
                ports_+: {
                  metrics: { containerPort: 9102 },
                },
                livenessProbe: {
                  httpGet: { path: "/", port: "metrics" },
                },
              },
            },
            initContainers_+: {
              elasticsearch_init: kube.Container("elasticsearch-init") {
                image: "alpine:3.6",
                command: ["/sbin/sysctl", "-w", "vm.max_map_count=262144"],
                securityContext: {
                  privileged: true,
                },
              },
            },
            // Generous grace period, to complete shard reallocation
            terminationGracePeriodSeconds: 5 * 60,
          },
        },
        volumeClaimTemplates_+: {
          datadir: kube.PersistentVolumeClaim("datadir") + $.namespace {
            storage: es.resources.disk + "Gi",
          },
        },
      },
    },

    svc: kube.Service($.p + "elasticsearch-logging") + $.namespace {
      target_pod: es.sts.spec.template,
    },
  },
}
