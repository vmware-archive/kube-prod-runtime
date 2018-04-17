local kube = import "kube.libsonnet";

{
  p:: "",
  namespace:: {metadata+: {namespace: "kube-system"}},

  Issuer(name):: kube._Object("certmanager.k8s.io/v1alpha1", "Issuer", name) {
  },

  ClusterIssuer(name):: kube._Object("certmanager.k8s.io/v1alpha1", "ClusterIssuer", name) {
  },

  certCRD: kube.CustomResourceDefinition("certmanager.k8s.io", "v1alpha1", "Certificate"),

  issuerCRD: kube.CustomResourceDefinition("certmanager.k8s.io", "v1alpha1", "Issuer"),

  clusterissuerCRD: kube.CustomResourceDefinition("certmanager.k8s.io", "v1alpha1", "ClusterIssuer") {
    spec+: {
      scope: "Cluster",
    },
  },

  sa: kube.ServiceAccount($.p+"cert-manager") + $.namespace,

  clusterRole: kube.ClusterRole($.p+"cert-manager") {
    rules: [
      {
        apiGroups: ["certmanager.k8s.io"],
        resources: ["certificates", "issuers", "clusterissuers"],
        // FIXME: audit - the helm chart just has "*"
        verbs: ["get", "list", "watch", "create", "patch", "update", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["secrets", "endpoints", "services", "pods"],
        // FIXME: audit - the helm chart just has "*"
        verbs: ["get", "list", "watch", "create", "patch", "update", "delete"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        // FIXME: audit - the helm chart just has "*"
        verbs: ["get", "list", "watch", "create", "patch", "update", "delete"],
      },
      {
        apiGroups: [""],
        resources: ["events"],
        verbs: ["create", "patch", "update"],
      },
    ],
  },

  clusterRoleBinding: kube.ClusterRoleBinding($.p+"cert-manager") {
    roleRef_: $.clusterRole,
    subjects_+: [$.sa],
  },

  deploy: kube.Deployment($.p+"cert-manager") + $.namespace {
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "9402",
            "prometheus.io/path": "/metrics",
          },
        },
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            default: kube.Container("cert-manager") {
              image: "quay.io/jetstack/cert-manager-controller:v0.2.4",
              args_+: {
                "cluster-resource-namespace": "$(POD_NAMESPACE)",
              },
              env_+: {
                POD_NAMESPACE: kube.FieldRef("metadata.namespace"),
              },
              ports_+: {
                prometheus: {containerPort: 9402},
              },
              resources: {
                requests: {cpu: "10m", memory: "32Mi"},
              },
            },
          },
        },
      },
    },
  },

  letsencryptStaging: $.ClusterIssuer($.p+"letsencrypt-staging") + $.namespace {
    local this = self,
    spec+: {
      acme+: {
        server: "https://acme-staging.api.letsencrypt.org/directory",
        email: std.extVar('EMAIL'),
        privateKeySecretRef: {name: this.metadata.name},
        http01: {},
      },
    },
  },

  letsencryptProd: $.letsencryptStaging {
    metadata+: {name: $.p+"letsencrypt-prod"},
    spec+: {
      acme+: {
        server: "https://acme-v01.api.letsencrypt.org/directory",
      },
    },
  },

  deployShim: kube.Deployment($.p+"cert-manager-ingress-shim") + $.namespace {
    spec+: {
      template+: {
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            default: kube.Container("ingress-shim") {
              image: "quay.io/jetstack/cert-manager-ingress-shim:v0.2.4",
              args_+: {
                // Used for Ingress with kubernetes.io/tls-acme=true
                default_issuer_:: $.letsencryptProd,
                "default-issuer-name": self.default_issuer_.metadata.name,
                "default-issuer-kind": self.default_issuer_.kind,
              },
              resources: {
                requests: {cpu: "10m", memory: "32Mi"},
              },
            },
          },
        },
      },
    },
  },
}
