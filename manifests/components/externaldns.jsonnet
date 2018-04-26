local kube = import "kube.libsonnet";

{
  p:: "",
  namespace:: {metadata+: {namespace: "kube-system"}},

  clusterRole: kube.ClusterRole($.p+"external-dns") {
    rules: [
      {
        apiGroups: [""],
        resources: ["services"],
        verbs: ["get", "watch", "list"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        verbs: ["get", "watch", "list"],
      },
    ],
  },

  clusterRoleBinding: kube.ClusterRoleBinding($.p+"external-dns-viewer") {
    roleRef_: $.clusterRole,
    subjects_+: [$.sa],
  },

  sa: kube.ServiceAccount($.p+"external-dns") + $.namespace,

  deploy: kube.Deployment($.p+"external-dns") + $.namespace {
    spec+: {
      template+: {
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            edns: kube.Container("external-dns") {
              image: "registry.opensource.zalan.do/teapot/external-dns:v0.5.0",
              args_+: {
                sources_:: ["service", "ingress"],
                //"domain-filter": "example.com",
              },
              args+: ["--source=%s" % s for s in self.args_.sources_],
            },
          },
        },
      },
    },
  },
}
