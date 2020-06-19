local kube = (import '../vendor/github.com/bitnami-labs/kube-libsonnet/kube.libsonnet');
local helpers = (import 'helpers.jsonnet');

// Create a (configured) kubeprod stock object
local kubeprod = (import '../tests/gke.jsonnet');

local PROMETHEUS_DEPLOY = 'prometheus.prometheus.deploy';
local do_test = (
  std.assertEqual(
    // jsonnet stock overrides
    kubeprod {
      prometheus+: {
        prometheus+: {
          deploy+: {
            metadata+: {
              annotations+: {
                foo: 'bar',
              },
            },
            spec+: {
              template+: {
                spec+: {
                  containers_+: {
                    default+: {
                      resources+: {
                        requests+: {
                          cpu: '42m',
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
    // vs using helpers.setAtPath()
    kubeprod
    // Add annotation
    + helpers.setAtPath(PROMETHEUS_DEPLOY + '.metadata.annotations', { foo: 'bar' })
    // Adjust requested CPU
    + helpers.setAtPath(PROMETHEUS_DEPLOY + '.spec.template.spec.containers_.default.resources.requests.cpu', '42m')
  )
);

// A convenient valid nil Kubernetes object (to satisfy kubecfg)
kube.List() {
  metadata: { annotation: { test: do_test } },
}
