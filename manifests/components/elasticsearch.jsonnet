local kube = import "../lib/kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "../lib/utils.libsonnet";

local ELASTICSEARCH_IMAGE = "bitnami/elasticsearch:5.6.4-r58";

{
  p:: "",
  namespace:: { metadata+: { namespace: "kube-system" } },

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
    roleRef_: $.elasticsearchRole,
    subjects_+: [$.serviceAccount],
  },

  disruptionBudget: kube.PodDisruptionBudget($.p+"elasticsearch-logging") + $.namespace {
    target_pod: $.sts.spec.template,
    spec+: { maxUnavailable: 1 },
  },

  sts: kube.StatefulSet($.p + "elasticsearch-logging") + $.namespace {
    local this = self,
    spec+: {
      replicas: 3,
      podManagementPolicy: "Parallel",
      template+: {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "9102",
          },
        },
        spec+: {
          affinity: {
            podAntiAffinity: {
              preferredDuringSchedulingIgnoredDuringExecution: [
                {
                  weight: 100,
                  podAffinityTerm: {
                    labelSelector: this.spec.selector,
                    topologyKey: "kubernetes.io/hostname",
                  },
                },
                {
                  weight: 10,
                  podAffinityTerm: {
                    labelSelector: this.spec.selector,
                    topologyKey: "failure-domain.beta.kubernetes.io/zone",
                  },
                },
              ],
            },
          },
          default_container: "elasticsearch",
          containers_+: {
            elasticsearch: kube.Container("elasticsearch") {
              local container = self,
              image: ELASTICSEARCH_IMAGE,
              // This can massively vary depending on the logging volume
              resources: {
                requests: { cpu: "100m", memory: "1200Mi" },
                limits: {
                  cpu: "1", // uses lots of CPU when indexing
                  memory: "2Gi",
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
                ELASTICSEARCH_SERVICE_NAME: $.svc.metadata.name,

                // Verify quorum requirements
                min_master_nodes:: 2,
                assert ($.sts.spec.replicas >= self.min_master_nodes &&
                        $.sts.spec.replicas < self.min_master_nodes * 2) :
                "Not enough quorum, verify min_master_nodes vs replicas",
                MINIMUM_MASTER_NODES: std.toString(self.min_master_nodes),

                // TODO: offer a dynamically sized pool of
                // non-master nodes.  Autoscaler will require custom
                // HPA metrics in practice.

                // NB: wrapper script always adds a -Xms value, so can't
                // just rely on -XX:+UseCGroupMemoryLimitForHeap
                local heapsize = kube.siToNum(container.resources.requests.memory) / std.pow(2, 20),
                ELASTICSEARCH_HEAP_SIZE: "%dm" % heapsize,
              },
              readinessProbe: {
                local probe = self,
                // don't allow rolling updates to kill containers until the cluster is green
                // ...meaning it's not allocating replicas or relocating any shards
                // FIXME: great idea in theory, breaks bootstrapping.
                //httpGet: { path: "/_cluster/health?local=true&wait_for_status=green&timeout=%ds" % probe.timeoutSeconds, port: "db" },
                httpGet: { path: "/_nodes/_local/version", port: "db" },
                timeoutSeconds: 5,
                initialDelaySeconds: 2 * 60,
                periodSeconds: 30,
                failureThreshold: 4,
              },
              livenessProbe: self.readinessProbe {
                httpGet: { path: "/_nodes/_local/version", port: "db" },

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
              // TODO: investigate feasibility of switching to https://kubernetes.io/docs/tasks/administer-cluster/sysctl-cluster/#setting-sysctls-for-a-pod
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
        datadir: { storage: "100Gi" },
      },
    },
  },

  svc: kube.Service($.p + "elasticsearch-logging") + $.namespace {
    target_pod: $.sts.spec.template,
    spec+: {clusterIP: "None"}, // headless
  },
}
