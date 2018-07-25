local kube = import "../lib/kube.libsonnet";

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
        apiGroups: [""],
        resources: ["pods"],
        verbs: ["get","watch","list"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        verbs: ["get", "watch", "list"],
      },
      {
        apiGroups: [""],
        resources: ["nodes"],
        verbs: ["list"],
      },
    ],
  },

  clusterRoleBinding: kube.ClusterRoleBinding($.p+"external-dns-viewer") {
    roleRef_: $.clusterRole,
    subjects_+: [$.sa],
  },

  sa: kube.ServiceAccount($.p+"external-dns") + $.namespace,

  deploy: kube.Deployment($.p+"external-dns") + $.namespace {
    local this = self,
    ownerId:: error "ownerId is required",
    spec+: {
      template+: {
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            edns: kube.Container("external-dns") {
              image: "bitnami/external-dns:0.5.4-r8",
              args_+: {
                sources_:: ["service", "ingress"],
                "txt-owner-id": this.ownerId,
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
