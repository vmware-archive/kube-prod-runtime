local kube = import "../lib/kube.libsonnet";

{
  deployment: kube.Deployment("crashloop") {
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            default: kube.Container("crashloop") {
              image: "busybox",
            },
          },
        },
      },
    },
  },
}
