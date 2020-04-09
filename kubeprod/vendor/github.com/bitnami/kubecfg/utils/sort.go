// Copyright 2017 The kubecfg authors
//
//
//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.

package utils

import (
	"sort"

	log "github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/discovery"
	"k8s.io/kube-openapi/pkg/util/proto"
)

var (
	gkTpr               = schema.GroupKind{Group: "extensions", Kind: "ThirdPartyResource"}
	gkCrd               = schema.GroupKind{Group: "apiextensions.k8s.io", Kind: "CustomResourceDefinition"}
	gkValidatingWebhook = schema.GroupKind{Group: "admissionregistration.k8s.io", Kind: "ValidatingWebhookConfiguration"}
	gkMutatingWebhook   = schema.GroupKind{Group: "admissionregistration.k8s.io", Kind: "MutatingWebhookConfiguration"}
)

// a podSpecVisitor traverses a schema tree and records whether the schema
// contains a PodSpec resource.
type podSpecVisitor bool

func (v *podSpecVisitor) VisitKind(k *proto.Kind) {
	if k.GetPath().String() == "io.k8s.api.core.v1.PodSpec" {
		*v = true
		return
	}
	for _, f := range k.Fields {
		f.Accept(v)
		if *v == true {
			return
		}
	}
}

func (v *podSpecVisitor) VisitReference(s proto.Reference)  { s.SubSchema().Accept(v) }
func (v *podSpecVisitor) VisitArray(s *proto.Array)         { s.SubType.Accept(v) }
func (v *podSpecVisitor) VisitMap(s *proto.Map)             { s.SubType.Accept(v) }
func (v *podSpecVisitor) VisitPrimitive(p *proto.Primitive) {}

var podSpecCache = map[string]podSpecVisitor{}

func containsPodSpec(disco discovery.OpenAPISchemaInterface, gvk schema.GroupVersionKind) bool {
	result, ok := podSpecCache[gvk.String()]
	if ok {
		return bool(result)
	}

	oapi, err := NewOpenAPISchemaFor(disco, gvk)
	if err != nil {
		log.Debugf("error fetching schema for %s: %v", gvk, err)
		return false
	}

	oapi.schema.Accept(&result)
	podSpecCache[gvk.String()] = result

	return bool(result)
}

// Arbitrary numbers used to do a simple topological sort of resources.
func depTier(disco discovery.OpenAPISchemaInterface, mapper meta.RESTMapper, o schema.ObjectKind) (int, error) {
	gvk := o.GroupVersionKind()
	gk := gvk.GroupKind()
	if gk == gkTpr || gk == gkCrd {
		// Special case (first): these create other types
		return 10, nil
	} else if gk == gkValidatingWebhook || gk == gkMutatingWebhook {
		// Special case (last): these require operational services
		return 200, nil
	}

	mapping, err := mapper.RESTMapping(gk, gvk.Version)
	if err != nil {
		log.Debugf("unable to fetch resource for %s (%v), continuing", gvk, err)
		return 50, nil
	}

	if mapping.Scope.Name() == meta.RESTScopeNameRoot {
		// Place global before namespaced
		return 20, nil
	} else if containsPodSpec(disco, gvk) {
		// (Potentially) starts a pod, so place last
		return 100, nil
	} else {
		// Everything else
		return 50, nil
	}
}

// DependencyOrder is a `sort.Interface` that *best-effort* sorts the
// objects so that known dependencies appear earlier in the list.  The
// idea is to prevent *some* of the "crash-restart" loops when
// creating inter-dependent resources.
func DependencyOrder(disco discovery.OpenAPISchemaInterface, mapper meta.RESTMapper, list []*unstructured.Unstructured) (sort.Interface, error) {
	sortKeys := make([]int, len(list))
	for i, item := range list {
		var err error
		sortKeys[i], err = depTier(disco, mapper, item.GetObjectKind())
		if err != nil {
			return nil, err
		}
	}
	log.Debugf("sortKeys is %v", sortKeys)
	return &mappedSort{sortKeys: sortKeys, items: list}, nil
}

type mappedSort struct {
	sortKeys []int
	items    []*unstructured.Unstructured
}

func (l *mappedSort) Len() int { return len(l.items) }
func (l *mappedSort) Swap(i, j int) {
	l.sortKeys[i], l.sortKeys[j] = l.sortKeys[j], l.sortKeys[i]
	l.items[i], l.items[j] = l.items[j], l.items[i]
}
func (l *mappedSort) Less(i, j int) bool {
	if l.sortKeys[i] != l.sortKeys[j] {
		return l.sortKeys[i] < l.sortKeys[j]
	}
	// Fall back to alpha sort, to give persistent order
	return AlphabeticalOrder(l.items).Less(i, j)
}

// AlphabeticalOrder is a `sort.Interface` that sorts the
// objects by namespace/name/kind alphabetical order
type AlphabeticalOrder []*unstructured.Unstructured

func (l AlphabeticalOrder) Len() int      { return len(l) }
func (l AlphabeticalOrder) Swap(i, j int) { l[i], l[j] = l[j], l[i] }
func (l AlphabeticalOrder) Less(i, j int) bool {
	a, b := l[i], l[j]

	if a.GetNamespace() != b.GetNamespace() {
		return a.GetNamespace() < b.GetNamespace()
	}
	if a.GetName() != b.GetName() {
		return a.GetName() < b.GetName()
	}
	return a.GetKind() < b.GetKind()
}
