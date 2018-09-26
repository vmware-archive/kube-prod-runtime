package integration

import (
	"encoding/json"
	"math/rand"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"

	appsv1beta1 "k8s.io/api/apps/v1beta1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"
)

var letterRunes = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

func init() {
	rand.Seed(time.Now().UnixNano())
}

func RandString(n int) string {
	b := make([]rune, n)
	for i := range b {
		b[i] = letterRunes[rand.Intn(len(letterRunes))]
	}
	return string(b)
}

type hits struct {
	Total int `json:"total"`
}

type apiResponse struct {
	Hits hits `json:"hits"`
}

func totalHits(resp *apiResponse) int {
	return resp.Hits.Total
}

// This test uses https://onsi.github.io/ginkgo/ - see there for docs
// on the slightly odd structure this imposes.
var _ = Describe("Logging", func() {
	var c kubernetes.Interface
	var deploy *appsv1beta1.Deployment
	var ns string

	BeforeEach(func() {
		c = kubernetes.NewForConfigOrDie(clusterConfigOrDie())
		ns = createNsOrDie(c.CoreV1(), "test-logging-")

		decoder := scheme.Codecs.UniversalDeserializer()

		deploy = decodeFileOrDie(decoder, "testdata/logging-deploy.yaml").(*appsv1beta1.Deployment)

		deploy.Spec.Template.Spec.Containers[0].Env[0].Value = RandString(32)
	})

	AfterEach(func() {
		// disable namespace deletion due to timeout issue experienced on AKS, TODO: re-enable
		// deleteNsOrDie(c.CoreV1(), ns)
	})

	JustBeforeEach(func() {
		var err error
		deploy, err = c.AppsV1beta1().Deployments(ns).Create(deploy)
		Expect(err).NotTo(HaveOccurred())
	})

	Context("basic", func() {
		// We create a container that repeatedly writes out a log signature to the
		// standard output and this test executes a query on elasticsearch to look up
		// the log signature
		It("should capture container logs", func() {
			Eventually(func() (*apiResponse, error) {
				var err error
				selector := "log:" + deploy.Spec.Template.Spec.Containers[0].Env[0].Value
				params := map[string]string{"q": selector}
				resultRaw, err := c.CoreV1().Services("kubeprod").ProxyGet("http", "elasticsearch-logging", "9200", "_search", params).DoRaw()
				if err != nil {
					return nil, err
				}

				resp := apiResponse{}
				json.Unmarshal(resultRaw, &resp)
				return &resp, err
			}, "15m", "5s").
				Should(WithTransform(totalHits, BeNumerically(">", 0)))
		})
	})
})
