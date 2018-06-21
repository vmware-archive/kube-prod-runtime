// Platform: Kubernetes 1.8.x on minikube 0.25 (with kubeadm bootstrapper)
//
// ```
// minikube --bootstrapper=kubeadm --kubernetes-version=v1.9.0
// ```
//

(import "minikube-common.libsonnet") {
  letsencrypt_contact_email:: std.extVar('EMAIL'),
}
