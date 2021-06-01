/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018-2019 Bitnami
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

package integration

import (
	"k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

// This test uses https://onsi.github.io/ginkgo/ - see there for docs
// on the slightly odd structure this imposes.
var _ = Describe("version", func() {
	var c kubernetes.Interface
	var configmap *v1.ConfigMap

	BeforeEach(func() {
		c = kubernetes.NewForConfigOrDie(clusterConfigOrDie())
	})

	JustBeforeEach(func() {
		var err error
		configmap, err = c.CoreV1().
			ConfigMaps("kubeprod").
			Get("release", metav1.GetOptions{})
		Expect(err).NotTo(HaveOccurred())
	})

	It("should contain release information", func() {
		Expect(configmap.Data).To(HaveKeyWithValue(
			"release",
			SatisfyAny(
				// local builds can also be versioned using the short git sha
				Equal("dev-untagged"),
				MatchRegexp(`[\da-g]{7}`),
				// release versions (starts with a v and don't have any extra suffixes)
				MatchRegexp(`v\d+\.\d+\.\d+`),
				// prelease versions (e.g.: suffixed with -rc1)
				MatchRegexp(`\d+\.\d+\.\d+(?:-.*)`),
			)))
	})
})
