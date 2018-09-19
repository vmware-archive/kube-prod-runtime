local kube = import "../lib/kube.libsonnet";
local utils = import "../lib/utils.libsonnet";

local ELASTICSEARCH_IMAGE = "bitnami/elasticsearch:5.6.4-r55";

// Mount point for the data volume (used by multiple containers, like the
// elasticsearch container and the elasticsearch-fs init container)
local ELASTICSEARCH_DATA_MOUNTPOINT = "/bitnami/elasticsearch/data";

// Mount point for the custom Java security properties configuration file
local JAVA_SECURITY_MOUNTPOINT = "/opt/bitnami/java/lib/security/java.security.custom";

local ELASTICSEARCH_HTTP_PORT = 9200;
local ELASTICSEARCH_TRANSPORT_PORT = 9300;

{
  p:: "",
  min_master_nodes:: 2,
  namespace:: error "namespace is undefined",

  labels:: {
    metadata+: {
      labels+: {
        "k8s-app": "elasticsearch-logging",
      },
    },
  },

  serviceAccount: kube.ServiceAccount($.p + "elasticsearch-logging") + $.labels {
    metadata+: {
      namespace: $.namespace,
    },
  },

  elasticsearchRole: kube.ClusterRole($.p + "elasticsearch-logging") + $.labels {
    metadata+: {
      namespace: $.namespace,
    },
    rules: [
      {
        apiGroups: [""],
        resources: ["services", "namespaces", "endpoints"],
        verbs: ["get"],
      },
    ],
  },

  elasticsearchBinding: kube.ClusterRoleBinding($.p + "elasticsearch-logging") + $.labels {
    roleRef_: $.elasticsearchRole,
    subjects_+: [$.serviceAccount],
  },

  disruptionBudget: kube.PodDisruptionBudget($.p+"elasticsearch-logging") + $.labels {
    metadata+: {
      namespace: $.namespace,
    },
    target_pod: $.sts.spec.template,
    spec+: { maxUnavailable: 1 },
  },

  // ConfigMap for additional Java security properties
  java_security: kube.ConfigMap($.p+"java-elasticsearch-logging") + $.labels {
    metadata+: {
      namespace: $.namespace,
    },
    data+: {
      "java.security": (importstr "elasticsearch-config/java.security"),
    },
  },

  sts: kube.StatefulSet($.p + "elasticsearch-logging") + $.labels {
    local this = self,
    metadata+: {
      namespace: $.namespace,
    },
    spec+: {
      podManagementPolicy: "Parallel",
      replicas: 3,
      updateStrategy: { type: "RollingUpdate" },
      template+: {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "9102",
          },
        },
        spec+: {
          serviceAccountName: $.serviceAccount.metadata.name,
          affinity: kube.PodZoneAntiAffinityAnnotation(this.spec.template),
          default_container: "elasticsearch_logging",
          volumes_+: {
            java_security: kube.ConfigMapVolume($.java_security),
          },
          securityContext: {
            fsGroup: 1001,
          },
          containers_+: {
            elasticsearch_logging: kube.Container("elasticsearch-logging") {
              local container = self,
              image: ELASTICSEARCH_IMAGE,
              // This can massively vary depending on the logging volume
              securityContext: {
                runAsUser: 1001,
              },
              resources: {
                requests: { cpu: "100m", memory: "1200Mi" },
                limits: {
                  cpu: "1", // uses lots of CPU when indexing
                  memory: "2Gi",
                },
              },
              ports_+: {
                db: { containerPort: ELASTICSEARCH_HTTP_PORT },
                transport: { containerPort: ELASTICSEARCH_TRANSPORT_PORT },
              },
              volumeMounts_+: {
                // Persistence for ElasticSearch data
                data: { mountPath: ELASTICSEARCH_DATA_MOUNTPOINT },
                java_security: {
                  mountPath: JAVA_SECURITY_MOUNTPOINT,
                  subPath: "java.security",
                  readOnly: true,
                },
              },
              env_+: {
                ELASTICSEARCH_CLUSTER_NAME: "elasticsearch-cluster",
                // TODO: offer a dynamically sized pool of non-master nodes.
                // Autoscaler will require custom HPA metrics in practice.
                assert ($.sts.spec.replicas >= $.min_master_nodes && $.sts.spec.replicas < $.min_master_nodes * 2) : "Not enough quorum, verify min_master_nodes vs replicas",
                ELASTICSEARCH_MINIMUM_MASTER_NODES: $.min_master_nodes,
                ELASTICSEARCH_PORT_NUMBER: ELASTICSEARCH_HTTP_PORT,
                ELASTICSEARCH_NODE_PORT_NUMBER: ELASTICSEARCH_TRANSPORT_PORT,
                ELASTICSEARCH_CLUSTER_HOSTS: $.svc.metadata.name,
                local heapsize = kube.siToNum(container.resources.requests.memory) / std.pow(2, 20),
                ES_JAVA_OPTS: std.join(" ", [
                  "-Djava.security.properties=%s" % JAVA_SECURITY_MOUNTPOINT,
                  "-Xms%dm" % heapsize, // ES asserts that these are equal
                  "-Xmx%dm" % heapsize,
                  "-XshowSettings:vm",
                ]),
              },
              readinessProbe: {
                httpGet: { path: "/_cluster/health?local=true", port: "db" },
                // don't allow rolling updates to kill containers until the cluster is green
                // ...meaning it's not allocating replicas or relocating any shards
                initialDelaySeconds: 120,
                periodSeconds: 30,
                failureThreshold: 4,
                successThreshold: 2,  // Minimum consecutive successes for the probe to be considered successful after having failed.
              },
              livenessProbe: self.readinessProbe {
                // elasticsearch_logging_discovery has a 5min timeout on cluster bootstrap
                initialDelaySeconds: 5 * 60,
                successThreshold: 1,  // Minimum consecutive successes for the probe to be considered successful after having failed.
              },
            },
            prom_exporter: kube.Container("prom-exporter") {
              image: "justwatch/elasticsearch_exporter:1.0.1",
              command: ["elasticsearch_exporter"],
              args_+: {
                "es.uri": "http://localhost:%s/" % ELASTICSEARCH_HTTP_PORT,
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
            elasticsearch_logging_init: kube.Container("elasticsearch-logging-init") {
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
        data: { storage: "100Gi" },
      },
    },
  },

  svc: kube.Service($.p + "elasticsearch-logging") + $.labels {
    target_pod: $.sts.spec.template,
    metadata+: {
      namespace: $.namespace,
      labels+: {
        "kubernetes.io/name": "Elasticsearch",
      },
      annotations+: {
        // From: https://github.com/kubernetes/dns/blob/master/docs/specification.md
        // An endpoint is considered ready if its address is in the addresses field
        // of the EndpointSubset object, or the corresponding service has the following
        // annotation set to true.
        "service.alpha.kubernetes.io/tolerate-unready-endpoints": "true",
      },
    },
    spec+: {
      clusterIP: "None",  // headless
      // Publish endpoints resolved by the service even if they are not yet ready.
      // This allows ElasticSearch to discover IPv4 addresses for all nodes from
      // the StatefulSet for master discovery, even if they haven't come up and are
      // yet ready.
      publishNotReadyAddresses: true,
      sessionAffinity: "None",
    },
  },
}
