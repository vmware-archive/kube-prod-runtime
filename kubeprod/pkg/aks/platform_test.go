package aks

import (
	"reflect"
	"testing"

	"k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

func TestToUnstructured(t *testing.T) {
	input := &v1.ConfigMap{
		ObjectMeta: metav1.ObjectMeta{
			Name: "foo",
		},
		Data: map[string]string{
			"baz": "xyzzy",
		},
	}

	expected := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"apiVersion": "v1",
			"kind":       "ConfigMap",
			"metadata": map[string]interface{}{
				"name":              "foo",
				"creationTimestamp": nil,
			},
			"data": map[string]interface{}{
				"baz": "xyzzy",
			},
		},
	}

	output, err := toUnstructured(input)
	if err != nil {
		t.Fatalf("toUnstructured failed with %v", err)
	}

	if !reflect.DeepEqual(output, expected) {
		t.Errorf("%#v != %#v", output, expected)
	}
}
