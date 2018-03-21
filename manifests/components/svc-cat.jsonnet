local kube = import "kube.libsonnet";
local kubecfg = import "kubecfg.libsonnet";

// TODO: move into kube.libsonnet
local APIService() = kube._Object("apiregistration.k8s.io/v1beta1", "APIService", "") {
  local this = self,
  metadata+: {
    // must be version.group
    name: "%s.%s" % [this.spec.version, this.spec.group],
    labels+: {name: this.metadata.name},
  },
  spec: {
    local spec = self,

    //caBundle?
    group: error "group is required",
    version: error "version is required",

    service_: error "service is required",
    service: {
      name: spec.service_.metadata.name,
      namespace: spec.service.metadata.namespace,
    },
  },
};


{
  p:: "service-catalog-",
  namespace:: {metadata+: {namespace: "kube-system"}},

  apiservice: APIService() {
    spec+: {
      group: "servicecatalog.k8s.io",
      version: "v1beta1",
      service_+: $.api.svc,
      groupPriorityMinimum: 10000,
      versionPriority: 20,
    },
  },

  etcd: {
    svc: error "Need an etcd cluster",
  },

  api: {
    sa: kube.ServiceAccount($.p+"apiserver") + $.namespace,

    clusterRole: kube.ClusterRole($.p+"apiserver") {
      rules: [{
        apiGroups: [""],
        resources: ["namespaces"],
        verbs: ["get", "list", "watch"],
      }],
    },

    clusterRoleBinding: kube.ClusterRoleBinding($.p+"apiserver") {
      roleRef_: $.api.clusterRole,
      subjects_+: [$.api.sa],
    },

    authDelegator: kube.ClusterRoleBinding($.p+"apiserver-auth-delegator") {
      roleRef: {
        apiGroup: "rbac.authorization.k8s.io",
        kind: "ClusterRole",
        name: "system:auth-delegator",
      },
      subjects_+: [$.api.sa],
    },

    apiserverAuthBinding: kube.RoleBinding($.p+"apiserver-auth-reader") + $.namespace {
      roleRef: {
        apiGroup: "rbac.authorization.k8s.io",
        kind: "Role",
        name: "extension-apiserver-authentication-reader",
      },
      subjects_+: [$.api.sa],
    },

    cert: kube.Secret($.p+"apiserver-cert") + $.namespace {
      type: "kubernetes.io/tls",
      data_+: {
        "tls.cert":: error "provided externally",
        "tls.key":: error "provided externally",
      },
    },

    svc: kube.Service($.p+"controller-manager") + $.namespace {
      target_pod: $.api.deploy.spec.template,
      port: 443,
    },

    deploy: kube.Deployment($.p+"controller-manager") + $.namespace {
      spec+: {
        template+: {
          spec+: {
            serviceAccountName: $.api.sa.metadata.name,
            volumes_+: {
              cert: kube.SecretVolume($.api.cert) {
                items+: [
                  {key: "tls.crt", path: "apiserver.crt"},
                  {key: "tls.key", path: "apiserver.key"},
                ],
              },
            },
            containers_+: {
              apiserver: kube.Container("apiserver") {
                image: kubecfg.resolveImage("quay.io/kubernetes-service-catalog/service-catalog:v0.1.9"),
                resources: {
                  requests: {cpu: "100m", memory: "20Mi"},
                  limits: {cpu: "100m", memory: "30Mi"},
                },
                command: ["apiserver"],
                args_+: {
                  admission_control_:: [
                    // NB: order is important
                    "KubernetesNamespaceLifecycle",
                    "DefaultServicePlan",
                    "ServiceBindingsLifecycle",
                    "ServicePlanChangeValidator",
                    "BrokerAuthSarCheck",
                  ],
                  "admission-control": std.join(",", self.admission_control_),
                  "secure-port": 8443,
                  "storage-type": "etcd",
                  "etcd-servers": $.etcd.svc.http_url,
                  "v": 6, // verbosity: 0-10
                  "serve-openapi-spec": true,
                },
                ports_+: {
                  https: {containerPort: 8443},
                },
                volumeMounts_+: {
                  cert: {mountPath: "/var/run/kubernetes-service-catalog", readOnly: true}
                },
                readinessProbe: {
                  httpGet: {port: 8443, path: "/healthz", scheme: "HTTPS"},
                  failureThreshold: 1,
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                  successThreshold: 1,
                  timeoutSeconds: 2,
                },
                livenessProbe: self.readinessProbe {
                  failureThreshold: 3,
                },
              },
            },
          },
        },
      },
    },
  },

  cm: {
    sa: kube.SerivceAccount($.p+"controller-manager") + $.namespace ,

    clusterRole: kube.ClusterRole($.p+"controller-manager") {
      rules: [
        {
          apiGroups: [""],
          resources: ["events"],
          verbs: ["create", "patch", "update"],
        },
        // fixme: non-global secrets get/create/update/delete from servicebindings
        {
          apiGroups: [""],
          resources: ["pods"],
          verbs: ["get", "list", "update", "patch", "watch", "delete", "initialize"],
        },
        {
          apiGroups: [""],
          resources: ["namespaces"],
          verbs: ["get", "list", "watch"],
        },
        {
          apiGroups: ["servicecatalog.k8s.io"],
          resources: ["clusterserviceclasses", "clusterserviceplans"],
          verbs: ["get", "list", "watch", "create", "patch", "update", "delete"],
        },
        {
          apiGroups: ["servicecatalog.k8s.io"],
          resources: ["clusterservicebrokers", "serviceinstances", "servicebindings"],
          verbs: ["get", "list", "watch"],
        },
        {
          apiGroups: ["servicecatalog.k8s.io"],
          resources: [r+"/status" for r in [
            "clusterservicebrokers", "clusterserviceclasses", "clusterserviceplans", "serviceinstances", "servicebindings"]] +
            ["serviceinstances/reference"],
          verbs: ["update"],
        },
      ],
    },

    clusterRoleBinding: kube.ClusterRoleBinding($.p+"controller-manager") {
      roleRef_: $.cm.clusterRole,
      subjects_+: [$.cm.sa],
    },

    lockRole: kube.Role($.p+"controller-manager-lock") + $.namespace {
      rules: [
        {
          apiGroups: [""],
          resources: ["configmaps"],
          verbs: ["create"],
        },
        {
          apiGroups: [""],
          resources: ["configmaps"],
          resourceNames: [$.p+"controller-manager"],
          verbs: ["get", "update"],
        },
      ],
    },

    lockRoleBinding: kube.RoleBinding($.p+"controller-manager-lock") + $.namespace {
      roleRef_: $.cm.lockRole,
      subjects_+: [$.cm.sa],
    },

    deploy: kube.Deployment($.p+"controller-manager") + $.namespace {
      metadata+: {
        annotations+: {
          "prometheus.io/scrape": "true",
        },
      },
      spec+: {
        template+: {
          spec+: {
            serviceAccountName: $.cm.sa.metadata.name,
            volumes_+: {
              cert: kube.SecretVolume($.api.cert) {
                items: [{key: "tls.crt", path: "apiserver.crt"}],
              },
            },
            containers_+: {
              cm: kube.Container("controller-manager") {
                image: "",
                resources+: {
                  requests: {cpu: "100m", memory: "20Mi"},
                  limits: {cpu: "100m", memory: "50Mi"},
                },
                env_+: {
                  K8S_NAMESPACE: kube.FieldRef("metadata.namespace"),
                },
                command: ["controller-manager"],
                args_+: {
                  port: 8080,
                  "leader-election-namespace": "$(K8S_NAMESPACE)",
                  "leader-elect-resource-lock": "configmaps",
                  "profiling": false,
                  "contention-profiling": false,
                  v: 6, // 0-10 verbosity
                  "resync-interval": "5m",
                  "broker-relist-interval": "24h",
                  feature_gates_:: ["OriginatingIdentity", "AsyncBindingOperations"],
                  "feature-gates": std.join(",", [g+"=true" for g in std.set(self.feature_gates_)]),
                },
                ports_+: {
                  default: {containerPort: 8080},
                },
                volumeMounts_+: {
                  cert: {mountPath: "/etc/service-catalog-ssl", readOnly: true},
                },
                readinessProbe: {
                  httpGet: {port: 8080, path: "/healthz"},
                  failureThreshold: 1,
                  initialDelaySeconds: 10,
                  periodSeconds: 10,
                  successThreshold: 1,
                  timeoutSeconds: 2,
                },
                livenessProbe: self.readinessProbe {
                  failureThreshold: 3,
                },
              },
            },
          },
        },
      },
    },
  },
}
