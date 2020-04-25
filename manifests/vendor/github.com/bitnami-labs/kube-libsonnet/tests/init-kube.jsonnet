local kube = import "../kube.libsonnet";

local crds = {
  // A simplified VPA CRD from https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
  vpa_crd: kube.CustomResourceDefinition("autoscaling.k8s.io", "v1beta1", "VerticalPodAutoscaler") {
    spec+: {
      versions+: [
        { name: "v1beta1", served: true, storage: false },
        { name: "v1beta2", served: true, storage: true },
      ],
    },
  },

};

crds
