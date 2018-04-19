local kube = import "kube.libsonnet";

local arch = "amd64";
local version = "v1.5.2";

{
  namespace:: {
    metadata+: { namespace: "kube-system" },
  },

  serviceAccount: kube.ServiceAccount("heapster") + $.namespace,

  clusterRoleBinding: kube.ClusterRoleBinding("heapster-binding") {
    roleRef: {
      apiGroup: "rbac.authorization.k8s.io",
      kind: "ClusterRole",
      name: "system:heapster",
    },
    subjects_: [$.serviceAccount],
  },

  nannyRole: kube.Role("pod-nanny") + $.namespace {
    metadata+: { name: "system:pod-nanny" },
    rules: [
      {
        apiGroups: [""],
        resources: ["pods"],
        verbs: ["get"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["deployments"],
        verbs: ["get", "update"],
      },
    ],
  },

  roleBinding: kube.RoleBinding("heapster-binding") + $.namespace {
    roleRef_: $.nannyRole,
    subjects_: [$.serviceAccount],
  },

  service: kube.Service("heapster") + $.namespace {
    target_pod: $.deployment.spec.template,
    port: 80,
  },

  deployment: kube.Deployment("heapster") + $.namespace {
    local this = self,

    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            "scheduler.alpha.kubernetes.io/critical-pod": "",
          },
        },
        spec+: {
          local this_containers = self.containers_,
          serviceAccountName: $.serviceAccount.metadata.name,
          nodeSelector+: {"beta.kubernetes.io/arch": arch},
          containers_+: {
            default: kube.Container("heapster") {
              image: "gcr.io/google_containers/heapster-%s:%s" % [arch, version],
              command: ["/heapster"],
              args_+: {
                source: "kubernetes.summary_api:''",
              },
              ports_+: {
                default: { containerPort: 8082 },
              },
              livenessProbe: {
                httpGet: { path: "/healthz", port: 8082, scheme: "HTTP" },
                initialDelaySeconds: 180,
                timeoutSeconds: 5,
              },
            },
            nanny: kube.Container("heapster-nanny") {
              image: "gcr.io/google_containers/addon-resizer-%s:2.1" % arch,
              command: ["/pod_nanny"],
              args_+: {
                cpu: "80m",
                "extra-cpu": "0.5m",
                memory: "140Mi",
                "extra-memory": "4Mi",
                deployment: this.metadata.name,
                container: this_containers.default.name,
                "poll-period": 300000,
              },
              resources: {
                limits: { cpu: "50m", memory: "90Mi" },
                requests: self.limits,
              },
              env_+: {
                MY_POD_NAME: kube.FieldRef("metadata.name"),
                MY_POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
            },
          },
        },
      },
    },
  },
}
