# Cluster-specific configuration
(import "/Users/falfaro/go/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/aks+k8s-1.9.jsonnet") {
	config:: import "kubeprod.json",
	// Place your overrides here
}