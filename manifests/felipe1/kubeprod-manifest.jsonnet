# Cluster-specific configuration
(import "/Users/falfaro/go/src/github.com/bitnami/kube-prod-runtime/manifests/platforms/aks+k8s-1.9.jsonnet") {
    config:: import "kubeprod-autogen.json",
    // Place your overrides here
    prometheus+: {
        monitoring_rules+: {
            ElasticsearchDown: {
                expr: "sum(elasticsearch_cluster_health_up) < 2",
                "for": "10m",
                labels: {severity: "critical"},
                annotations: {
                    summary: "Elastichsearch is unhealthy",
                    description: "Elasticsearch cluster quorum is not healthy",
                },
            },
        },
    }
}
