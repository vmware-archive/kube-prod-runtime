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
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"strings"

	admin "cloud.google.com/go/iam/admin/apiv1"
	log "github.com/sirupsen/logrus"
	flag "github.com/spf13/pflag"
	"golang.org/x/oauth2/google"
	crm "google.golang.org/api/cloudresourcemanager/v1"
	dns "google.golang.org/api/dns/v1"
	gensupport "google.golang.org/api/gensupport"
	"google.golang.org/api/googleapi"
	adminpb "google.golang.org/genproto/googleapis/iam/admin/v1"

	"github.com/bitnami/kube-prod-runtime/kubeprod/tools"
)

func init() {
	gensupport.RegisterHook(debugHook)
}

func debugHook(ctx context.Context, req *http.Request) func(resp *http.Response) {
	// Note to debuggers: Re-running with GODEBUG=http2debug=2 env var set may also be useful.
	log.Debugf("-> %#v", req)
	return func(resp *http.Response) {
		log.Debugf("<- %#v", resp)
	}
}

func defaultProject() string {
	// No "nice" golang API for this: https://github.com/golang/oauth2/issues/241

	type Output struct {
		Core struct {
			Project string `json:"project"`
		} `json:"core"`
	}

	out, err := exec.Command("gcloud", "-q", "config", "list", "core/project", "--format=json").Output()
	if err != nil {
		log.Debugf("failed to get default gcloud project: 'gcloud config list core/project' failed with %v", err)
		return ""
	}

	var output Output
	if err := json.Unmarshal(out, &output); err != nil {
		log.Debugf("unable to decode 'gcloud config list' output: %v", err)
		return ""
	}

	return output.Core.Project
}

func getProject(flags *flag.FlagSet) (string, error) {
	project, err := flags.GetString(flagProject)
	if err != nil {
		return "", err
	}

	if project == "" {
		project = defaultProject()
	}

	if project == "" {
		return "", fmt.Errorf("no gcloud default found, explicit --project flag is required")
	}

	return project, nil
}

func prompt(question, def string) (string, error) {
	w := bufio.NewWriter(os.Stdout)
	fmt.Fprintf(w, "%s", question)
	if def != "" {
		fmt.Fprintf(w, " [%s]", def)
	}
	fmt.Fprintf(w, "? ")
	_ = w.Flush()

	r := bufio.NewReader(os.Stdin)
	result, err := r.ReadString('\n')
	if err != nil {
		return "", err
	}
	result = strings.TrimSpace(result)
	if result == "" {
		result = def
	}
	return result, nil
}

func hasGoogStatusCode(err error, code int) bool {
	e, ok := err.(*googleapi.Error)
	return ok && e.Code == code
}

var notAlnumRe = regexp.MustCompile("[^a-z0-9]+")

func accountID(s string) string {
	s = notAlnumRe.ReplaceAllLiteralString(strings.ToLower(s), "-")

	// Account IDs are restricted to 6..30 chars
	if len(s) < 6 {
		s += "xxxxxxx"[:6-len(s)]
	} else if len(s) > 30 {
		s = s[:30]
	}

	// .. and must match [a-z][a-z\d\-]*[a-z\d]
	// Handle suffix here.  Prefix is always correct by
	// construction (otherwise server API will fail with a
	// suitable error)
	s = strings.TrimRight(s, "-")

	return s
}

func stringArrayContains(array []string, element string) bool {
	for _, x := range array {
		if x == element {
			return true
		}
	}
	return false
}

func addIamBinding(policy *crm.Policy, role, member string) {
	var binding *crm.Binding
	for _, b := range policy.Bindings {
		if b.Role == role {
			binding = b
			break
		}
	}
	if binding == nil {
		binding = &crm.Binding{
			Role:    role,
			Members: make([]string, 0, 1),
		}
		policy.Bindings = append(policy.Bindings, binding)
	}

	if !stringArrayContains(binding.Members, member) {
		binding.Members = append(binding.Members, member)
	}
}

func (conf *GKEConfig) Generate(ctx context.Context) error {
	flags := conf.flags

	// Leaks secrets to log!
	//log.Debugf("Input config: %#v", conf)

	if conf.ContactEmail == "" {
		email, err := flags.GetString(flagEmail)
		if err != nil {
			return err
		}
		conf.ContactEmail = email
	}

	if conf.DnsZone == "" {
		domain, err := flags.GetString(flagDNSSuffix)
		if err != nil {
			return err
		}
		conf.DnsZone = domain
	}

	if conf.DnsZone != "" {
		//
		// externaldns setup
		//

		if conf.ExternalDNS.Project == "" {
			project, err := getProject(flags)
			if err != nil {
				return err
			}
			conf.ExternalDNS.Project = project
		}

		googClient, err := google.DefaultClient(ctx, dns.CloudPlatformScope, crm.CloudPlatformScope)
		if err != nil {
			return fmt.Errorf("failed to initialise Google API client: %v", err)
		}

		dnsService, err := dns.New(googClient)
		if err != nil {
			return fmt.Errorf("failed to initialise Google DNS API client: %v", err)
		}

		zone, err := dnsService.ManagedZones.
			Create(conf.ExternalDNS.Project, &dns.ManagedZone{
				Name:        accountID("bkpr-" + conf.DnsZone),
				DnsName:     conf.DnsZone + ".",
				Description: "Created by BKPR installer",
			}).
			Context(ctx).
			Do()
		if err != nil {
			if hasGoogStatusCode(err, http.StatusConflict) {
				log.Infof("Using existing Google DNS zone %q", conf.DnsZone)
			} else {
				return fmt.Errorf("failed to create Google managed-zone %q: %v", conf.DnsZone, err)
			}
		} else {
			log.Infof("Created Google managed-zone %q", conf.DnsZone)
			log.Infof("You will need to ensure glue records exist for %s pointing to NS %v", conf.DnsZone, zone.NameServers)
		}

		if conf.ExternalDNS.Credentials == "" {
			client, err := admin.NewIamClient(ctx)
			if err != nil {
				return fmt.Errorf("failed to intialise Google IAM client: %v", err)
			}
			defer client.Close()

			accountID := accountID("bkpr-edns-" + conf.DnsZone)

			log.Debugf("Creating service account %q in project %q", accountID, conf.ExternalDNS.Project)
			sa, err := client.CreateServiceAccount(ctx, &adminpb.CreateServiceAccountRequest{
				Name:      admin.IamProjectPath(conf.ExternalDNS.Project),
				AccountId: accountID,
				ServiceAccount: &adminpb.ServiceAccount{
					DisplayName: fmt.Sprintf("kubeprod service account for %q external-dns", conf.DnsZone),
				},
			})
			if err != nil {
				return err
			}
			log.Infof("Created service account %s", sa.Email)

			crmService, err := crm.New(googClient)
			if err != nil {
				return fmt.Errorf("failed to construct Google oauth client: %v", err)
			}

			policy, err := crmService.Projects.
				GetIamPolicy(conf.ExternalDNS.Project, &crm.GetIamPolicyRequest{}).
				Context(ctx).
				Do()
			if err != nil {
				return fmt.Errorf("failed to get IAM policy for project %q: %v",
					conf.ExternalDNS.Project, err)
			}

			addIamBinding(policy, "roles/dns.admin", "serviceAccount:"+sa.Email)

			policy, err = crmService.Projects.
				SetIamPolicy(conf.ExternalDNS.Project, &crm.SetIamPolicyRequest{
					Policy: policy,
				}).
				Context(ctx).
				Do()
			if err != nil {
				// FIXME: retry on etag conflict
				return fmt.Errorf("failed to set IAM policy on project %q: user lacks "+
					"privileges to grant roles/dns.admin role to service account %s: %v",
					conf.ExternalDNS.Project, sa.Email, err)
			}
			log.Infof("Granted roles/dns.admin to service account %s", sa.Email)

			key, err := client.CreateServiceAccountKey(ctx, &adminpb.CreateServiceAccountKeyRequest{
				Name:           sa.Name,
				PrivateKeyType: adminpb.ServiceAccountPrivateKeyType_TYPE_GOOGLE_CREDENTIALS_FILE,
			})
			if err != nil {
				return err
			}

			conf.ExternalDNS.Credentials = string(key.PrivateKeyData)
		}
	}

	//
	// oauth2-proxy setup
	//

	log.Debug("Starting oauth2-proxy setup")

	if conf.OauthProxy.CookieSecret == "" {
		// I Quote: cookie_secret must be 16, 24, or 32 bytes
		// to create an AES cipher when pass_access_token ==
		// true or cookie_refresh != 0
		secret, err := tools.Base64RandBytes(24)
		if err != nil {
			return err
		}
		conf.OauthProxy.CookieSecret = secret
	}

	if conf.OauthProxy.AuthzDomain == "" {
		domain, err := flags.GetString(flagAuthzDomain)
		if err != nil {
			return err
		}
		conf.OauthProxy.AuthzDomain = domain
	}

	if conf.OauthProxy.GoogleGroups == nil {
		// Avoid json `null`
		groups, err := flags.GetStringSlice(flagOauthGoogleGroups)
		if err != nil {
			return err
		}
		conf.OauthProxy.GoogleGroups = groups
	}

	needsGoogleGroups := len(conf.OauthProxy.GoogleGroups) > 0

	if needsGoogleGroups && conf.OauthProxy.GoogleAdminEmail == "" {
		client, err := admin.NewIamClient(ctx)
		if err != nil {
			return err
		}
		defer client.Close()

		project, err := getProject(flags)
		if err != nil {
			return err
		}

		accountID := accountID("bkpr-oauth2-" + conf.DnsZone)

		sa, err := client.CreateServiceAccount(ctx, &adminpb.CreateServiceAccountRequest{
			Name:      admin.IamProjectPath(project),
			AccountId: accountID,
			ServiceAccount: &adminpb.ServiceAccount{
				DisplayName: fmt.Sprintf("kubeprod service account for %q oauth2-proxy", conf.DnsZone),
			},
		})
		if err != nil {
			return err
		}
		log.Infof("Created service account %s", sa.Email)

		// FIXME: add directory scopes

		key, err := client.CreateServiceAccountKey(ctx, &adminpb.CreateServiceAccountKeyRequest{
			Name:           sa.Name,
			PrivateKeyType: adminpb.ServiceAccountPrivateKeyType_TYPE_GOOGLE_CREDENTIALS_FILE,
		})
		if err != nil {
			return err
		}

		conf.OauthProxy.GoogleAdminEmail = sa.Email
		conf.OauthProxy.GoogleServiceAccountJson = string(key.PrivateKeyData)
	}

	if conf.OauthProxy.ClientID == "" || conf.OauthProxy.ClientSecret == "" {
		var err error
		clientID := conf.OauthProxy.ClientID
		clientSecret := conf.OauthProxy.ClientSecret

		if clientID == "" {
			clientID, err = flags.GetString(flagOauthClientId)
			if err != nil {
				return err
			}
		}

		if clientSecret == "" {
			clientSecret, err = flags.GetString(flagOauthClientSecret)
			if err != nil {
				return err
			}
		}

		oauthHosts := []string{"prometheus", "kibana", "grafana"}
		replyUrls := make([]string, len(oauthHosts))
		for i, h := range oauthHosts {
			replyUrls[i] = fmt.Sprintf("https://%s.%s/oauth2/callback", h, conf.DnsZone)
		}

		if clientID == "" || clientSecret == "" {
			project, err := getProject(flags)
			if err != nil {
				return err
			}

			fmt.Println("Google does not provide an API to automatically configure OAuth sign-in, so this part is manual.")
			fmt.Println("Go to this URL and complete the following steps:")
			fmt.Printf("  https://console.cloud.google.com/apis/credentials?project=%s\n", url.QueryEscape(project))
			fmt.Println("1. Choose \"OAuth consent screen\" tab in center pane.")
			fmt.Println("2. Fill in \"Application name\".")
			fmt.Printf("3. Make sure %q is listed under the \"Authorized domains\" section\n", conf.DnsZone)
			fmt.Println("4. Save your changes.")
			fmt.Println("5. Choose \"Credentials\" tab in center pane.")
			fmt.Println("6. Click \"Create credentials\" button and choose \"OAuth client ID\".")
			fmt.Println("7. Choose \"Web application\", and fill in a name.")
			fmt.Println("8. Fill in the \"Authorised redirect URIs\" with:")
			for _, u := range replyUrls {
				fmt.Printf("     %s\n", u)
			}
			fmt.Println("9. Click \"Create\"")

			clientID, err = prompt("Client ID", clientID)
			if err != nil {
				return err
			}
			clientSecret, err = prompt("Client secret", clientSecret)
			if err != nil {
				return err
			}
		}

		conf.OauthProxy.ClientID = clientID
		conf.OauthProxy.ClientSecret = clientSecret
	}

	return nil
}
