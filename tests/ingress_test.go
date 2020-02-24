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
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/ioutil"
	"net"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"regexp"
	"time"

	"github.com/pusher/oauth2_proxy/cookie"
	appsv1beta1 "k8s.io/api/apps/v1beta1"
	"k8s.io/api/core/v1"
	xv1beta1 "k8s.io/api/extensions/v1beta1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

// TODO: We should store enough information in the cluster to be able to extract this post-install.
var dnsSuffix = flag.String("dns-suffix", "", "DNS suffix to use for test hostnames.  Empty disables hostname-based tests")

// TLS client with LetsEncrypt "staging" root certificate added, and the
// ability to override hostname lookup.
// `hosts` is really endpoints: map{"google.com:443": "1.2.3.4:8443"}
func httpClient(hosts *map[string]string) (*http.Client, error) {
	rootCAs, _ := x509.SystemCertPool()
	if rootCAs == nil {
		rootCAs = x509.NewCertPool()
	}

	certs, err := ioutil.ReadFile("testdata/fakelerootx1.pem")
	if err != nil {
		return nil, err
	}

	if ok := rootCAs.AppendCertsFromPEM(certs); !ok {
		return nil, fmt.Errorf("No certs appended")
	}

	jar, err := cookiejar.New(&cookiejar.Options{})
	if err != nil {
		return nil, err
	}

	dialer := &net.Dialer{
		Timeout:   30 * time.Second,
		KeepAlive: 30 * time.Second,
		DualStack: true,
	}
	dialContext := func(ctx context.Context, network, addr string) (net.Conn, error) {
		if new, ok := (*hosts)[addr]; ok {
			fmt.Fprintf(GinkgoWriter, "Using endpoint %s for %s\n", new, addr)
			addr = new
		}
		return dialer.DialContext(ctx, network, addr)
	}

	config := &tls.Config{
		RootCAs: rootCAs,
	}
	transport := &http.Transport{
		MaxIdleConns:          100,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,

		DialContext:     dialContext,
		TLSClientConfig: config,
	}
	return &http.Client{
		Transport:     transport,
		Jar:           jar,
		CheckRedirect: PrintRedirects(GinkgoWriter, DefaultCheckRedirect),
	}, nil
}

func statusCode(resp *http.Response) int {
	return resp.StatusCode
}

func isPrivateIP(ip string) bool {
	var privateBlocks []*net.IPNet

	for _, cidr := range []string{
		"127.0.0.0/8",    // IPv4 loopback
		"10.0.0.0/8",     // RFC1918
		"172.16.0.0/12",  // RFC1918
		"192.168.0.0/16", // RFC1918
		"::1/128",        // IPv6 loopback
		"fe80::/10",      // IPv6 link-local
	} {
		_, block, _ := net.ParseCIDR(cidr)
		privateBlocks = append(privateBlocks, block)
	}

	IP := net.ParseIP(ip)
	for _, block := range privateBlocks {
		if block.Contains(IP) {
			return true
		}
	}
	return false
}

func getURL(client *http.Client, url string) (*http.Response, error) {
	resp, err := client.Get(url)
	fmt.Fprintf(GinkgoWriter, "GET %v -> %v, %v\n", url, resp, err)
	return resp, err
}

// This test uses https://onsi.github.io/ginkgo/ - see there for docs
// on the slightly odd structure this imposes.
var _ = Describe("Ingress", func() {
	var c kubernetes.Interface
	var ing *xv1beta1.Ingress
	var deploy *appsv1beta1.Deployment
	var svc *v1.Service
	var ns string

	BeforeEach(func() {
		c = kubernetes.NewForConfigOrDie(clusterConfigOrDie())
		ns = createNsOrDie(c.CoreV1(), "test-ing-")

		decoder := scheme.Codecs.UniversalDeserializer()

		deploy = decodeFileOrDie(decoder, "testdata/ingress-deploy.yaml").(*appsv1beta1.Deployment)

		svc = decodeFileOrDie(decoder, "testdata/ingress-service.yaml").(*v1.Service)

		ing = decodeFileOrDie(decoder, "testdata/ingress-ingress.yaml").(*xv1beta1.Ingress)

		suffix := *dnsSuffix
		if suffix == "" {
			suffix = "kubeprod.test"
		}
		ing.Spec.Rules[0].Host = fmt.Sprintf("%s.%s", ns, suffix)
	})

	AfterEach(func() {
		deleteNs(c.CoreV1(), ns)
	})

	JustBeforeEach(func() {
		var err error
		deploy, err = c.AppsV1beta1().Deployments(ns).Create(deploy)
		Expect(err).NotTo(HaveOccurred())

		svc, err = c.CoreV1().Services(ns).Create(svc)
		Expect(err).NotTo(HaveOccurred())

		ing, err = c.ExtensionsV1beta1().Ingresses(ns).Create(ing)
		Expect(err).NotTo(HaveOccurred())
	})

	Context("basic", func() {
		It("Ingress LB should have a public IP", func() {
			Eventually(func() (string, error) {
				var lbAddr string
				var err error
				ing2, err := c.ExtensionsV1beta1().Ingresses(ns).Get(ing.Name, metav1.GetOptions{})
				if err != nil {
					return "", err
				}

				fmt.Fprintf(GinkgoWriter, "%s/%s: Ingress.Status.LB.Ingress is %v\n", ing2.Namespace, ing2.Name, ing2.Status.LoadBalancer.Ingress)

				for _, lbIng := range ing2.Status.LoadBalancer.Ingress {
					if lbIng.Hostname != "" {
						addrs, err := net.LookupHost(lbIng.Hostname)
						if err != nil {
							return "", err
						}
						lbAddr = addrs[0]
					} else if lbIng.IP != "" && lbAddr == "" {
						lbAddr = lbIng.IP
					}
				}
				if lbAddr == "" {
					return "", fmt.Errorf("ingress Status.LoadBalancer.Ingress is empty")
				}

				return lbAddr, nil
			}, "10m", "5s").
				ShouldNot(WithTransform(isPrivateIP, BeTrue()))
		})

		It("should be reachable via http URL", func() {
			url := fmt.Sprintf("http://%s", ing.Spec.Rules[0].Host)
			var resp *http.Response

			Eventually(func() (*http.Response, error) {
				var err error
				ing2, err := c.ExtensionsV1beta1().Ingresses(ns).Get(ing.Name, metav1.GetOptions{})
				if err != nil {
					return nil, err
				}

				fmt.Fprintf(GinkgoWriter, "%s/%s: Ingress.Status.LB.Ingress is %v\n", ing2.Namespace, ing2.Name, ing2.Status.LoadBalancer.Ingress)

				var lbAddr string
				for _, lbIng := range ing2.Status.LoadBalancer.Ingress {
					if lbIng.Hostname != "" {
						lbAddr = lbIng.Hostname
					} else if lbIng.IP != "" && lbAddr == "" {
						lbAddr = lbIng.IP
					}
				}
				if lbAddr == "" {
					return nil, fmt.Errorf("ingress Status.LoadBalancer.Ingress is empty")
				}

				client, err := httpClient(&map[string]string{
					net.JoinHostPort(ing.Spec.Rules[0].Host, "80"): net.JoinHostPort(lbAddr, "80"),
				})
				if err != nil {
					return nil, err
				}

				resp, err = getURL(client, url)
				return resp, err
			}, "10m", "5s").
				Should(WithTransform(statusCode, Equal(200)))

			defer resp.Body.Close()
			body, err := ioutil.ReadAll(resp.Body)
			Expect(err).NotTo(HaveOccurred())

			Expect(body).To(ContainSubstring("x-real-ip="))
			r := regexp.MustCompile(`(?m)^x-real-ip=(.*)$`)
			realIP := r.FindSubmatch(body)[1]
			// Ideally we would verify that this address
			// was a true local address but unfortunately
			// NAT makes that hard to check in the general
			// case.  Settle for not-rfc1918, which should
			// work in all cases except where the test is
			// being run "close" to the target cluster.
			// Will probably need to revisit for minikube :(
			Expect(string(realIP)).NotTo(WithTransform(isPrivateIP, BeTrue()))
		})
	})

	Context("with TLS", func() {
		BeforeEach(func() {
			if *dnsSuffix == "" {
				// This test requires a real DNS suffix, because letsencrypt
				Skip("--dns-suffix was not provided")
			}

			metav1.SetMetaDataAnnotation(&ing.ObjectMeta, "kubernetes.io/tls-acme", "true")
			metav1.SetMetaDataAnnotation(&ing.ObjectMeta, "cert-manager.io/cluster-issuer", "letsencrypt-staging")
			ing.Spec.TLS = []xv1beta1.IngressTLS{{
				Hosts:      []string{ing.Spec.Rules[0].Host},
				SecretName: fmt.Sprintf("%s-tls", ing.GetName()),
			}}
		})

		It("should be reachable via https URL", func() {
			url := fmt.Sprintf("https://%s", ing.Spec.Rules[0].Host)
			var resp *http.Response

			client, err := httpClient(&map[string]string{})
			Expect(err).NotTo(HaveOccurred())

			Eventually(func() (*http.Response, error) {
				resp, err = getURL(client, url)
				return resp, err
			}, "15m", "5s").
				Should(WithTransform(statusCode, Equal(200)))

			defer resp.Body.Close()
			body, err := ioutil.ReadAll(resp.Body)
			Expect(err).NotTo(HaveOccurred())

			Expect(body).To(ContainSubstring("x-real-ip="))
			r := regexp.MustCompile(`(?m)^x-real-ip=(.*)$`)
			realIP := r.FindSubmatch(body)[1]
			// Ideally we would verify that this address
			// was a true local address but unfortunately
			// NAT makes that hard to check in the general
			// case.  Settle for not-rfc1918, which should
			// work in all cases except where the test is
			// being run "close" to the target cluster.
			// Will probably need to revisit for minikube :(
			Expect(string(realIP)).NotTo(WithTransform(isPrivateIP, BeTrue()))
		})

		Context("with OAuth2", func() {
			BeforeEach(func() {
				pfx := fmt.Sprintf("https://auth.%s/oauth2", *dnsSuffix)
				metav1.SetMetaDataAnnotation(&ing.ObjectMeta, "nginx.ingress.kubernetes.io/auth-signin", pfx+"/start?rd=%2F$server_name$escaped_request_uri")
				metav1.SetMetaDataAnnotation(&ing.ObjectMeta, "nginx.ingress.kubernetes.io/auth-url", pfx+"/auth")
				metav1.SetMetaDataAnnotation(&ing.ObjectMeta, "nginx.ingress.kubernetes.io/auth-response-headers", "X-Auth-Request-User, X-Auth-Request-Email")
			})

			It("Should redirect to oauth2 server", func() {
				testUrl := fmt.Sprintf("https://%s/some/path", ing.Spec.Rules[0].Host)
				var resp *http.Response

				client, err := httpClient(&map[string]string{})
				Expect(err).NotTo(HaveOccurred())

				// NB: Google will return status 400, because our test cluster's redirect_uri has not been configured.
				// See also https://issuetracker.google.com/issues/116182848
				Eventually(func() (*http.Response, error) {
					// NB: will follow redirects
					resp, err = getURL(client, testUrl)
					return resp, err
				}, "15m", "5s").
					Should(WithTransform(statusCode, Or(Equal(200), Equal(400))))

				fmt.Fprintf(GinkgoWriter, "Response:\n%#v", resp)

				// Verify it redirected to a plausibly-correct login URL.
				// Expand as necessary
				Expect(resp.Request.URL.Host).To(Or(
					Equal("id."+*dnsSuffix),
					Equal("accounts.google.com"),
					Equal("login.microsoftonline.com"),
					MatchRegexp(`^cognito-idp\..*\.amazonaws\.com$`),
					MatchRegexp(`^.*\.auth\..*\.amazoncognito\.com$`),
				))
			})

			It("Authenticated requests should reach server", func() {
				// Ideally we would test using real
				// upstream credentials (offline auth
				// token), but that needs test
				// accounts, etc configured
				// beforehand.  Instead, this test
				// cheats and abuses access to the
				// oauth2_proxy cookie secret to
				// contrive a cookie that oauth2_proxy
				// just assumes is valid.

				testUrl := fmt.Sprintf("https://%s/some/path", ing.Spec.Rules[0].Host)

				var resp *http.Response

				client, err := httpClient(&map[string]string{})
				Expect(err).NotTo(HaveOccurred())

				secrets, err := c.CoreV1().Secrets("kubeprod").List(metav1.ListOptions{LabelSelector: "name=oauth2-proxy"})
				Expect(err).NotTo(HaveOccurred())
				Expect(secrets.Items).To(HaveLen(1))
				secret := secrets.Items[0]

				// Inject an auth cookie
				now := time.Now()
				cookieSecret := string(secret.Data["cookie_secret"])
				emailDom := string(secret.Data["authz_domain"])
				if emailDom == "*" {
					emailDom = "example.com"
				}
				email := "testuser@" + emailDom

				session := SessionState{
					AccessToken:  "fakeaccesstoken",
					IDToken:      "fakeidtoken",
					ExpiresOn:    now.Add(12 * time.Hour),
					RefreshToken: "fakerefreshtoken",
					Email:        email,
					User:         "testuser",
				}
				cookies, err := oauth2ProxyCookie(cookieSecret, session, now)
				Expect(err).NotTo(HaveOccurred())
				u, err := url.Parse(testUrl)
				Expect(err).NotTo(HaveOccurred())
				client.Jar.SetCookies(u, cookies)

				Eventually(func() (*http.Response, error) {
					// NB: will follow redirects
					resp, err = getURL(client, testUrl)
					return resp, err
				}, "15m", "5s").
					Should(WithTransform(statusCode, Equal(200)))

				fmt.Fprintf(GinkgoWriter, "Response:\n%#v", resp)

				defer resp.Body.Close()
				body, err := ioutil.ReadAll(resp.Body)
				Expect(err).NotTo(HaveOccurred())

				b := string(body)
				fmt.Fprintf(GinkgoWriter, "Body:\n%s", b)

				Expect(b).To(ContainSubstring("x-auth-request-user=" + session.User))
				Expect(b).To(ContainSubstring("x-auth-request-email=" + session.Email))
				Expect(b).To(ContainSubstring("real path=/some/path"))
				Expect(b).NotTo(ContainSubstring("authentication"))
			})
		})
	})
})

// SessionState is used to store information about the currently authenticated user session
type SessionState struct {
	AccessToken  string    `json:",omitempty"`
	IDToken      string    `json:",omitempty"`
	ExpiresOn    time.Time `json:"-"`
	RefreshToken string    `json:",omitempty"`
	Email        string    `json:",omitempty"`
	User         string    `json:",omitempty"`
}

type SessionStateJSON struct {
	*SessionState
	ExpiresOn *time.Time `json:",omitempty"`
}

func (s *SessionState) EncodeSessionState(c *cookie.Cipher) (string, error) {
	var ss SessionState
	var err error

	ss = *s
	if ss.AccessToken != "" {
		ss.AccessToken, err = c.Encrypt(ss.AccessToken)
		if err != nil {
			return "", err
		}
	}
	if ss.IDToken != "" {
		ss.IDToken, err = c.Encrypt(ss.IDToken)
		if err != nil {
			return "", err
		}
	}
	if ss.RefreshToken != "" {
		ss.RefreshToken, err = c.Encrypt(ss.RefreshToken)
		if err != nil {
			return "", err
		}
	}

	// Embed SessionState and ExpiresOn pointer into SessionStateJSON
	ssj := &SessionStateJSON{SessionState: &ss}
	if !ss.ExpiresOn.IsZero() {
		ssj.ExpiresOn = &ss.ExpiresOn
	}
	b, err := json.Marshal(ssj)
	return string(b), err
}

func oauth2ProxyCookie(cookieSecret string, session SessionState, now time.Time) ([]*http.Cookie, error) {
	const cookieName = "_oauth2_proxy"

	cipher, err := cookie.NewCipher([]byte(cookieSecret))
	if err != nil {
		return nil, err
	}

	s, err := session.EncodeSessionState(cipher)
	if err != nil {
		return nil, err
	}

	value := cookie.SignedValue(cookieSecret, cookieName, s, now)

	// Cookie value+name must be <4kiB
	Expect(len(value)).To(BeNumerically("<", 4096-len(cookieName)))

	return []*http.Cookie{
		{
			Name:     cookieName, // --cookie-name
			Value:    value,
			Path:     "/",
			Domain:   *dnsSuffix, // --cookie-domain
			HttpOnly: true,       // --cookie-httponly
			Secure:   true,       // --cookie-secure
			Expires:  now.Add(1 * time.Hour),
		},
	}, nil
}

// net/http CheckRedirect type alias.  Just to make the below
// prototype more readable ...
type redirectPolicy = func(req *http.Request, via []*http.Request) error

// PrintRedirects wraps a redirect policy callback in print statements
func PrintRedirects(w io.Writer, f redirectPolicy) redirectPolicy {
	return func(req *http.Request, via []*http.Request) error {
		fmt.Fprintf(w, "Redirect: -> %s\n", req.URL)
		err := f(req, via)
		if err != nil {
			fmt.Fprintf(w, "Redirect: (%v)\n", err)
		}
		return err
	}
}

// DefaultCheckRedirect is a duplicate of (private) http.defaultCheckRedirect
func DefaultCheckRedirect(req *http.Request, via []*http.Request) error {
	if len(via) >= 10 {
		return errors.New("stopped after 10 redirects")
	}
	return nil
}
