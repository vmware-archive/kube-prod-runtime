local kube = import "../lib/kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";
local utils = import "../lib/utils.libsonnet";

local ELASTICSEARCH_IMAGE = "bitnami/elasticsearch:6.3.2-r26";

// Mount point for the data volume (used by multiple containers, like the
// elasticsearch container and the elasticsearch-fs init container)
local ELASTICSEARCH_DATA_MOUNTPOINT = "/bitnami/elasticsearch/data";

{
  p:: "",
  min_master_nodes:: 2,
  namespace:: { metadata+: { namespace: "kube-system" } },

  // ElasticSearch additional (custom) configuration
  elasticsearch_config:: {
    // Used for discovery of ElasticSearch nodes via a Kubernetes
    // headless (without a ClusterIP) service.
    "discovery.zen.ping.unicast.hosts": $.svc.metadata.name,
    // Verify quorum requirements.
    assert ($.sts.spec.replicas >= $.min_master_nodes &&
            $.sts.spec.replicas < $.min_master_nodes * 2) :
    "Not enough quorum, verify min_master_nodes vs replicas",
    // TODO: offer a dynamically sized pool of non-master nodes.
    // Autoscaler will require custom HPA metrics in practice.
    "discovery.zen.minimum_master_nodes": $.min_master_nodes,
  },

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

  // ConfigMap for ElasticSearch additional (custom) configuration
  config: kube.ConfigMap($.p+"elasticsearch-logging") + $.namespace {
    data+: {
      "elasticsearch_custom.yml": kubecfg.manifestYaml($.elasticsearch_config),
    },
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
          serviceAccountName: $.serviceAccount.metadata.name,
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
          volumes_+: { config: kube.ConfigMapVolume($.config) },
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
                // Persistence for ElasticSearch data
                datadir: { mountPath: ELASTICSEARCH_DATA_MOUNTPOINT },
                // ElasticSearch additional (custom) configuration
                config: {
                  mountPath: "/bitnami/elasticsearch/conf/elasticsearch_custom.yml",
                  subPath: "elasticsearch_custom.yml",
                  readOnly: true,
                },
              },
              env_+: {
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
            // Fix permissions for the data volume
            elasticsearch_fs: kube.Container("elasticsearch-fs") {
              image: "busybox",
              command: ["chown", "-R", "1001:1001", ELASTICSEARCH_DATA_MOUNTPOINT],
              volumeMounts_+: {
                datadir: { mountPath: ELASTICSEARCH_DATA_MOUNTPOINT },
              },
              securityContext: {
                privileged: true,
              },
            },
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
    metadata+: {
      annotations+: {
        "service.alpha.kubernetes.io/tolerate-unready-endpoints": "true",
      },
    },
    spec+: {
      clusterIP: "None",  // headless
      publishNotReadyAddresses: true,
      sessionAffinity: "None",
    },
  },
}
