module github.com/bitnami/kube-prod-runtime/tests

go 1.14

require (
	github.com/googleapis/gnostic v0.1.1-0.20180317205109-6d7ae43a9ae9 // indirect
	github.com/hpcloud/tail v1.0.1-0.20180514194441-a1dbeea552b7 // indirect
	github.com/onsi/ginkgo v1.10.1
	github.com/onsi/gomega v1.7.0
	github.com/pusher/oauth2_proxy v3.2.0+incompatible
	gopkg.in/fsnotify/fsnotify.v1 v1.4.7 // indirect
	k8s.io/api v0.17.4
	k8s.io/apimachinery v0.17.4
	k8s.io/client-go v0.17.4
)

replace (
	github.com/Azure/go-autorest => github.com/Azure/go-autorest v13.3.3+incompatible

	// NB: pinning gnostic to v0.4.0 as v0.4.1 renamed s/OpenAPIv2/openapiv2/ at
	//       https://github.com/googleapis/gnostic/pull/155,
	//     while k8s.io/client-go/discovery@v0.17 still uses OpenAPIv2,
	//     even as of 2020/04/09 there's no released k8s.io/client-go/discovery version
	//     (latest 0.18.1) fixed to use openapiv2
	github.com/googleapis/gnostic => github.com/googleapis/gnostic v0.4.0
)
