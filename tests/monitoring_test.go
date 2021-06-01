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
	"encoding/json"
	"fmt"
	"time"

	"github.com/onsi/gomega/types"
	appsv1 "k8s.io/api/apps/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/ginkgo/extensions/table"
	. "github.com/onsi/gomega"
)

const am_path = "/alertmanager"
const am_alertname = "CrashLooping_test"

type Series struct {
	Alertname string `json:"alertname"`
	Container string `json:"container"`
	Namespace string `json:"namespace"`
}

type label struct {
	Alertname string `json:"alertname"`
	Container string `json:"container"`
	Namespace string `json:"namespace"`
}

type status struct {
	State string `json:"state"`
}

type alert struct {
	Label  label  `json:"labels"`
	Status status `json:"status"`
}

type endpoint struct {
	Url string `json:"url"`
}

type alertmanager struct {
	Active  []endpoint `json:"activeAlertmanagers"`
	Dropped []endpoint `json:"droppedAlertmanagers"`
}

type promResponse struct {
	Status string          `json:"status"`
	Data   json.RawMessage `json:"data"`
}

func countSeries(series []Series) int {
	return len(series)
}

func countEndpoints(endpoints []endpoint) int {
	return len(endpoints)
}

func countAlerts(alerts []alert) int {
	return len(alerts)
}

var _ = Describe("Exporters", func() {
	var c kubernetes.Interface

	BeforeEach(func() {
		c = kubernetes.NewForConfigOrDie(clusterConfigOrDie())
	})

	DescribeTable("Exported timeseries", func(selector string, match types.GomegaMatcher) {
		params := map[string]string{
			"match[]": selector,
			"start":   fmt.Sprintf("%d", time.Now().Add(-20*time.Minute).Unix()),
		}

		Eventually(func() ([]map[string]string, error) {
			var series []map[string]string
			resultRaw, err := c.CoreV1().
				Services("kubeprod").
				ProxyGet("http", "prometheus", "9090", "api/v1/series", params).
				DoRaw()
			if err != nil {
				return nil, err
			}

			resp := promResponse{}
			json.Unmarshal(resultRaw, &resp)
			json.Unmarshal(resp.Data, &series)

			return series, err
		}, "10m", "5s").Should(match)
	},
		Entry("prometheus", `prometheus_tsdb_head_chunks{kubernetes_namespace="kubeprod",name="prometheus"}`, Not(BeEmpty())),
		Entry("alertmanager", `alertmanager_peer_position`, Not(BeEmpty())),
		Entry("kube-state-metrics", `kube_deployment_status_replicas{kubernetes_namespace="kubeprod",deployment="nginx-ingress-controller"}`, Not(BeEmpty())),
		Entry("node-exporter", `node_cpu_seconds_total`, Not(BeEmpty())),
		// The next expectation assumes some certificates have been requested recently. This check can
		// fail for many reasons (e.g.: BKPR was installed a while ago and this test gets executed first
		// among the whole suite). A suggested change would be to isolate this expectation with an explcit
		// certificate resource creation to verify that this metric is exported. This would follow a
		// known pattern of Arrange, Act, and Assert. When running locally, this line may need to be
		// commented out.
		Entry("cert-manager", `certmanager_http_acme_client_request_count`, Not(BeEmpty())),
		Entry("elasticsearch", `elasticsearch_cluster_health_number_of_nodes{cluster="elasticsearch-cluster"}`, And(
			ContainElement(HaveKeyWithValue("kubernetes_pod_name", "elasticsearch-logging-0")),
			ContainElement(HaveKeyWithValue("kubernetes_pod_name", "elasticsearch-logging-1")),
			ContainElement(HaveKeyWithValue("kubernetes_pod_name", "elasticsearch-logging-2")),
		)),
		Entry("fluentd-es", `fluentd_output_status_buffer_total_bytes{type="elasticsearch"}`, Not(BeEmpty())),
		Entry("external-dns", `process_start_time_seconds{kubernetes_namespace="kubeprod",name="external-dns"}`, Not(BeEmpty())),
		Entry("nginx-ingress", `nginx_ingress_controller_nginx_process_requests_total{controller_namespace="kubeprod",controller_class="nginx"}`, Not(BeEmpty())),
	)
})

var _ = Describe("Monitoring", func() {
	var c kubernetes.Interface
	var deploy *appsv1.Deployment
	var ns string

	BeforeEach(func() {
		c = kubernetes.NewForConfigOrDie(clusterConfigOrDie())
		ns = createNsOrDie(c.CoreV1(), "test-monitoring-")
		decoder := scheme.Codecs.UniversalDeserializer()
		deploy = decodeFileOrDie(decoder, "testdata/monitoring-deploy.yaml").(*appsv1.Deployment)
	})

	AfterEach(func() {
		deleteNs(c.CoreV1(), ns)
	})

	JustBeforeEach(func() {
		var err error
		deploy, err = c.AppsV1().Deployments(ns).Create(deploy)
		Expect(err).NotTo(HaveOccurred())
	})

	Context("basic", func() {
		// This test makes a query to the prometheus API to check if prometheus is
		// monitoring the container launched by the test.
		It("should monitor container", func() {
			var series []Series
			Eventually(func() ([]Series, error) {
				selector := fmt.Sprintf("kube_pod_container_info{namespace=\"%s\",container=\"%s\"}", ns, deploy.Spec.Template.Spec.Containers[0].Name)
				params := map[string]string{"match[]": selector}
				resultRaw, err := c.CoreV1().Services("kubeprod").ProxyGet("http", "prometheus", "9090", "api/v1/series", params).DoRaw()
				if err != nil {
					return nil, err
				}

				resp := promResponse{}
				json.Unmarshal(resultRaw, &resp)
				json.Unmarshal(resp.Data, &series)

				return series, err
			}, "10m", "5s").
				Should(WithTransform(countSeries, BeNumerically(">", 0)))

			Expect(series[0].Container).To(Equal(deploy.Spec.Template.Spec.Containers[0].Name))
			Expect(series[0].Namespace).To(Equal(ns))
		})

		// This test queries the prometheus api to check if the alertmanagers
		// are auto-discovered
		It("should discover alertmanagers in the cluster", func() {
			var managers alertmanager
			Eventually(func() ([]endpoint, error) {
				params := map[string]string{}
				resultRaw, err := c.CoreV1().Services("kubeprod").ProxyGet("http", "prometheus", "9090", "api/v1/alertmanagers", params).DoRaw()
				if err != nil {
					return nil, err
				}

				resp := promResponse{}
				json.Unmarshal(resultRaw, &resp)
				json.Unmarshal(resp.Data, &managers)

				return managers.Active, err
			}, "10m", "5s").
				Should(WithTransform(countEndpoints, BeNumerically(">", 0)))

			Expect(managers.Active[0].Url).To(ContainSubstring(am_path + "/api/v2/alerts"))
		})
	})

	Context("a CrashLoop", func() {
		BeforeEach(func() {
			deploy.Spec.Template.Spec.Containers[0].Command = []string{"echo"}
		})

		// In this test we configure the container such that it enters a CrashLoop
		// The test passes successfully if prometheus reports that the container
		// has entered a CrashLoop
		It("should detect the crashing container", func() {
			var series []Series
			Eventually(func() ([]Series, error) {
				selector := fmt.Sprintf("ALERTS{namespace=\"%s\",container=\"%s\",alertname=\"%s\",alertstate=\"firing\"}", ns, deploy.Spec.Template.Spec.Containers[0].Name, am_alertname)
				params := map[string]string{"match[]": selector}
				resultRaw, err := c.CoreV1().Services("kubeprod").ProxyGet("http", "prometheus", "9090", "api/v1/series", params).DoRaw()
				if err != nil {
					return nil, err
				}

				resp := promResponse{}
				json.Unmarshal(resultRaw, &resp)
				json.Unmarshal(resp.Data, &series)

				return series, err
			}, "10m", "5s").
				Should(WithTransform(countSeries, BeNumerically(">", 0)))

			Expect(series[0].Container).To(Equal(deploy.Spec.Template.Spec.Containers[0].Name))
			Expect(series[0].Namespace).To(Equal(ns))
			Expect(series[0].Alertname).To(Equal(am_alertname))
		})

		// In this test we test if the alertmanager api reports the CrashLooping container
		It("alertmanager api reports the crashing container", func() {
			var alerts []alert
			Eventually(func() ([]alert, error) {
				filter := fmt.Sprintf("\"namespace=%s\",\"container=%s\",\"alertname=%s\"}", ns, deploy.Spec.Template.Spec.Containers[0].Name, am_alertname)
				params := map[string]string{"active": "true", "filter": filter}
				resultRaw, err := c.CoreV1().Services("kubeprod").ProxyGet("http", "alertmanager", "9093", am_path+"/api/v1/alerts", params).DoRaw()
				if err != nil {
					return nil, err
				}

				resp := promResponse{}
				json.Unmarshal(resultRaw, &resp)
				json.Unmarshal(resp.Data, &alerts)

				return alerts, err
			}, "10m", "5s").
				Should(WithTransform(countAlerts, BeNumerically(">", 0)))

			Expect(alerts[0].Label.Container).To(Equal(deploy.Spec.Template.Spec.Containers[0].Name))
			Expect(alerts[0].Label.Namespace).To(Equal(ns))
			Expect(alerts[0].Label.Alertname).To(Equal(am_alertname))
		})
	})
})
