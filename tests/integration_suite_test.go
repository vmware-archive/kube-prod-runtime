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
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"testing"

	"github.com/onsi/ginkgo/config"
	"github.com/onsi/ginkgo/reporters"
	"k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	corev1 "k8s.io/client-go/kubernetes/typed/core/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"

	"k8s.io/apimachinery/pkg/runtime"

	// For client auth plugins
	_ "k8s.io/client-go/plugin/pkg/client/auth"
)

var junitDir = flag.String("junit", "", "Write junit results to dir if specified")
var kubeconfig = flag.String("kubeconfig", "", "absolute path to the kubeconfig file")
var description = flag.String("description", "kube-prod-runtime integration tests", "suite description")

func clusterConfigOrDie() *rest.Config {
	var config *rest.Config
	var err error

	if *kubeconfig != "" {
		config, err = clientcmd.BuildConfigFromFlags("", *kubeconfig)
	} else {
		config, err = rest.InClusterConfig()
	}
	if err != nil {
		panic(err.Error())
	}

	return config
}

func createNsOrDie(c corev1.NamespacesGetter, ns string) string {
	result, err := c.Namespaces().Create(
		&v1.Namespace{
			ObjectMeta: metav1.ObjectMeta{
				GenerateName: ns,
			},
		})
	if err != nil {
		panic(err.Error())
	}
	name := result.GetName()
	fmt.Fprintf(GinkgoWriter, "Created namespace %s\n", name)
	return name
}

func deleteNsOrDie(c corev1.NamespacesGetter, ns string) {
	if ns == "" {
		return
	}
	err := c.Namespaces().Delete(ns, &metav1.DeleteOptions{})
	if err != nil {
		panic(err.Error())
	}
}

// `deleteNs`  attempts to delete a namespace without panicing on errors.
// Generally `deleteNsOrDie` should be used for the namespace deletion, but is
// known to fail on AKS due to connection timeout issues.
func deleteNs(c corev1.NamespacesGetter, ns string) {
	if ns == "" {
		return
	}
	err := c.Namespaces().Delete(ns, &metav1.DeleteOptions{})
	if err != nil {
		fmt.Println(err.Error())
	}
}

func decodeFile(decoder runtime.Decoder, path string) (runtime.Object, error) {
	buf, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, err
	}
	obj, _, err := decoder.Decode(buf, nil, nil)
	return obj, err
}

func decodeFileOrDie(decoder runtime.Decoder, path string) runtime.Object {
	obj, err := decodeFile(decoder, path)
	Expect(err).NotTo(HaveOccurred())
	return obj
}

func TestE2e(t *testing.T) {
	var myReporters []Reporter
	RegisterFailHandler(Fail)

	if *junitDir != "" {
		if err := os.MkdirAll(*junitDir, 0777); err != nil {
			t.Fatalf("Failed to create %s: %v", *junitDir, err)
		}
		fname := fmt.Sprintf("junit_%d.xml", config.GinkgoConfig.ParallelNode)
		junitReporter := reporters.NewJUnitReporter(filepath.Join(*junitDir, fname))
		myReporters = append(myReporters, junitReporter)
	}

	RunSpecsWithDefaultAndCustomReporters(t, *description, myReporters)
}
