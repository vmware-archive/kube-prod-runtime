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
	"fmt"

	log "github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/discovery"
	"k8s.io/kube-openapi/pkg/util/proto"
	"k8s.io/kube-openapi/pkg/util/proto/validation"
	"k8s.io/kubernetes/pkg/kubectl/cmd/util/openapi"
)

// OpenAPISchema represents an OpenAPI schema for a given GroupVersionKind.
type OpenAPISchema struct {
	schema proto.Schema
}

// NewOpenAPISchemaFor returns the OpenAPISchema object ready to validate objects of given GroupVersion
func NewOpenAPISchemaFor(delegate discovery.OpenAPISchemaInterface, gvk schema.GroupVersionKind) (*OpenAPISchema, error) {
	log.Debugf("Fetching schema for %v", gvk)
	doc, err := delegate.OpenAPISchema()
	if err != nil {
		return nil, err
	}
	res, err := openapi.NewOpenAPIData(doc)
	if err != nil {
		return nil, err
	}

	sc := res.LookupResource(gvk)
	if sc == nil {
		gvr := schema.GroupResource{
			// TODO(mkm): figure out a meaningful group+resource for schemas.
			Group:    "schema",
			Resource: "schema",
		}
		return nil, errors.NewNotFound(gvr, fmt.Sprintf("%s", gvk))
	}
	return &OpenAPISchema{schema: sc}, nil
}

// Validate is the primary entrypoint into this class
func (s *OpenAPISchema) Validate(obj *unstructured.Unstructured) []error {
	gvk := obj.GroupVersionKind()
	log.Infof("validate object %q", gvk)
	return validation.ValidateModel(obj.UnstructuredContent(), s.schema, fmt.Sprintf("%s.%s", gvk.Version, gvk.Kind))
}
