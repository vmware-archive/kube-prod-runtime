local kube = import "../lib/kube.libsonnet";

{
  p:: "",
  namespace:: {metadata+: {namespace: "kube-system"}},

  svc: kube.Service($.p+"etcd") + $.namespace {
    target_pod: $.etcd.spec.template,
    port: 2379,
  },

  etcd: kube.StatefulSet($.p+"etcd") + $.namespace {
    spec+: {
      replicas: 3,
      volumeClaimTemplates_+: {
        data: {storage: "10Gi"},
      },
      podManagementPolicy: "Parallel",
      template+: {
        spec+: {
          terminationGracePeriodSeconds: 30,
          containers_+: {
            etcd: kube.Container("etcd") {
              image: "quay.io/coreos/etcd:v3.3.1",
              resources+: {
                requests: {cpu: "100m", memory: "20Mi"},
                limits: {cpu: "100m", memory: "30Mi"},
              },
              env_+: {
                ETCD_DATA_DIR: "/etcd-data",
              },
              command: ["/usr/local/bin/etcd"],
              args_+: {
                "listen-client-urls": "http://0.0.0.0:2379",
                // important: no trailing slash:
                "advertise-client-urls": "http://" + $.svc.host_colon_port,
              },
              ports_+: {
                default: {containerPort: 2379},
              },
              volumeMounts_+: {
                data: {mountPath: "/etcd-data"},
              },
              readinessProbe: {
                httpGet: {port: 2379, path: "/health"},
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
}
