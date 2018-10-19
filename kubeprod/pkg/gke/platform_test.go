/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018 Bitnami
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package gke

import (
	"testing"

	crm "google.golang.org/api/cloudresourcemanager/v1"
)

func TestStringArrayContains(t *testing.T) {
	t.Parallel()

	a := []string{"Athos", "Porthos", "Aramis"}

	for _, test := range []struct {
		elem   string
		result bool
	}{
		{"Athos", true},
		{"Porthos", true},
		{"Aramis", true},
		{"d'Artagnan", false},
		{"", false},
	} {
		if res := stringArrayContains(a, test.elem); res != test.result {
			t.Errorf("Item %q result was %v", test.elem, res)
		}
	}
}

func TestAccountID(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		input, output string
	}{
		{"boringid", "boringid"},
		{"some-id-with-dashes", "some-id-with-dashes"},
		{"MixEdCase", "mixedcase"},
		{"ba.d_cha!r'*s", "ba-d-cha-r-s"},
		{"", "xxxxxx"},
		{"short", "shortx"},
		{"veryveryverylooongid-longer-than-thirty-chars", "veryveryverylooongid-longer-th"},
		{"kubeprod-edns-one-k8s-1-9.gke.fuloi.com", "kubeprod-edns-one-k8s-1-9-gke"}, // no trailing '-'
	} {
		if res := accountID(test.input); res != test.output {
			t.Errorf("Input %q produced %q, not %q", test.input, res, test.output)
		}
	}

}

func TestAddIamBinding(t *testing.T) {
	t.Parallel()

	policy := crm.Policy{
		Bindings: []*crm.Binding{
			{
				Members: []string{
					"user:mike@example.com",
					"group:admins@example.com",
					"domain:google.com",
					"serviceAccount:my-other-app@appspot.gserviceaccount.com",
				},
				Role: "roles/owner",
			},
			{
				Members: []string{
					"user:sean@example.com",
				},
				Role: "roles/viewer",
			},
		},
	}

	addIamBinding(&policy, "roles/owner", "domain:google.com")
	addIamBinding(&policy, "roles/viewer", "serviceAccount:foo")
	addIamBinding(&policy, "roles/dns.admin", "serviceAccount:bar")

	if len(policy.Bindings[0].Members) != 4 {
		t.Errorf("Adding existing member was not a noop.  New members: %v", policy.Bindings[0].Members)
	}

	if len(policy.Bindings[1].Members) != 2 {
		t.Fatalf("Incorrect roles/viewer members: %v", policy.Bindings[1].Members)
	}
	if policy.Bindings[1].Members[1] != "serviceAccount:foo" {
		t.Errorf("Failed to add viewer member. Members: %v", policy.Bindings[1].Members)
	}

	if len(policy.Bindings) != 3 {
		t.Fatalf("Unexpected number of bindings: %d != 3", len(policy.Bindings))
	}
	if policy.Bindings[2].Role != "roles/dns.admin" {
		t.Errorf("Created incorrect binding role: %v", policy.Bindings[2])
	}
	if len(policy.Bindings[2].Members) != 1 ||
		policy.Bindings[2].Members[0] != "serviceAccount:bar" {
		t.Errorf("Created incorrect binding members: %v", policy.Bindings[2])
	}
}
