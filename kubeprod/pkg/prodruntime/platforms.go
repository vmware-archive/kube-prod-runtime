package prodruntime

import (
	"fmt"
	"net/url"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	restclient "k8s.io/client-go/rest"
)

type Platform struct {
	Name        string
	Description string
	PreUpdate   func(objs []*unstructured.Unstructured) ([]*unstructured.Unstructured, error)
	PostUpdate  func(conf *restclient.Config) error
}

var Platforms = []Platform{
	{
		Name:        "minikube-0.25+k8s-1.9",
		Description: "Minikube 0.25 with Kubernetes 1.9",
	},
	{
		Name:        "minikube-0.25+k8s-1.8",
		Description: "Minikube 0.25 with Kubernetes 1.8",
	},
	{
		Name:        "aks+k8s-1.9",
		Description: "Azure Container Service (AKS) with Kubernetes 1.9",
	},
	{
		Name:        "aks+k8s-1.8",
		Description: "Azure Container Service (AKS) with Kubernetes 1.8",
	},
}

func FindPlatform(name string) *Platform {
	for i := range Platforms {
		p := &Platforms[i]
		if p.Name == name {
			return p
		}
	}
	return nil
}

func (p *Platform) ManifestURL(base *url.URL) (*url.URL, error) {
	return base.Parse(fmt.Sprintf("platforms/%s.jsonnet", p.Name))
}

func (p *Platform) RunPreUpdate(objs []*unstructured.Unstructured) ([]*unstructured.Unstructured, error) {
	if p.PreUpdate == nil {
		return objs, nil
	}
	return p.PreUpdate(objs)
}

func (p *Platform) RunPostUpdate(conf *restclient.Config) error {
	if p.PostUpdate == nil {
		return nil
	}
	return p.PostUpdate(conf)
}
