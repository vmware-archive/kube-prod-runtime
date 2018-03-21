local kube = import "kube.libsonnet";

// See https://github.com/GoogleCloudPlatform/k8s-service-catalog

{
  p:: "",

  oauthSecret: kube.Secret($.p+"google-oauth") {
    local this = self,
    data_+: {
      key: null, // long-lived service account json key goes here
      scopes: '["https://www.googleapis.com/auth/cloud-platform"]',
      secretName: "gcp-svc-account-secret",
      secretNamespace: this.metadata.namespace,
    },
  },

  sa: kube.ServiceAccount($.p+"google-oauth"),

  oauthClusterRole: kube.ClusterRole($.p+"google-oauth") {
    // TODO: ouch.  This should be significantly narrower scope.
    rules: [
      {
        apiGroups: [""],
        resources: ["secrets"],
        verbs: ["get", "list", "watch", "create", "update", "patch", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["namespaces"],
        verbs: ["get", "list", "watch"],
      },
    ],
  },

  oauthClusterRoleBinding: kube.ClusterRoleBinding($.p+"google-oauth") {
    roleRef_: $.oauthClusterRole,
    subjects_+: [$.sa],
  },

  deploy: kube.Deployment($.p+"google-oauth") {
    spec+: {
      template+: {
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            oauth: kube.Container("catalog-oauth") {
              image: "gcr.io/gcp-services/catalog-oauth:latest",  // FIXME: release?
              args_+: {
                n: "$(POD_NAMESPACE)",
                v: 6,
                alsologtostderr: true,
              },
              env_+: {
                POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              ports_+: {
                default: {containerPort: 8443},
              },
              resources+: {
                requests: {cpu: "100m", memory: "20Mi"},
                limits: {cpu: "100m", memory: "30Mi"},
              },
            },
          },
        },
      },
    },
  },
}
