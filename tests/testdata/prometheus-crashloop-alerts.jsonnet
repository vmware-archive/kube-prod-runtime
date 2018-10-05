local kubecfg = import "kubecfg.libsonnet";

{
  rules+: {
    test_:: {
      groups: [
        {
          name: "test.rules",
          rules: [
            {
              alert: "CrashLooping_test",
              expr: "sum(rate(kube_pod_container_status_restarts[10m])) BY (namespace, container) * 600 > 0",
              labels: {severity: "notice"},
            },
          ],
        },
      ],
    },
    "test.yaml": kubecfg.manifestYaml(self.test_),
  },

  am_config+: {
    route+: {
      group_interval: "30s",
      repeat_interval: "1m",
    },
  },
}
