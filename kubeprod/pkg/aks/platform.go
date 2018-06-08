package aks

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/services/authorization/mgmt/2015-07-01/authorization"
	"github.com/Azure/azure-sdk-for-go/services/dns/mgmt/2018-03-01-preview/dns"
	"github.com/Azure/azure-sdk-for-go/services/graphrbac/1.6/graphrbac"
	"github.com/Azure/azure-sdk-for-go/services/resources/mgmt/2018-02-01/resources"
	"github.com/Azure/go-autorest/autorest"
	"github.com/Azure/go-autorest/autorest/azure"
	azcli "github.com/Azure/go-autorest/autorest/azure/cli"
	"github.com/Azure/go-autorest/autorest/date"
	"github.com/Azure/go-autorest/autorest/to"
	"github.com/golang/glog"
	"github.com/satori/go.uuid"
	log "github.com/sirupsen/logrus"
	"k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/scheme"
)

const (
	userAgent = "Bitnami/kubeprod" // TODO: version
)

var (
	subIDParam     = paramNew("subscription-id", "Azure subscription ID")
	tenantIDParam  = paramNew("tenant-id", "Azure tenant ID")
	dnsZoneParam   = paramNew("dns-zone", "External DNS zone for public endpoints")
	dnsResgrpParam = paramNew("dns-resource-group", "Resource group of external DNS zone")
)

func init() {
	if err := initParams(); err != nil {
		log.Debugf("Unable to initialize azure-cli defaults: %v", err)
	}
}

func initParams() error {
	path, err := azcli.ProfilePath()
	if err != nil {
		return fmt.Errorf("Unable to find azure-cli profile: %v", err)
	}
	profile, err := azcli.LoadProfile(path)
	if err != nil {
		return fmt.Errorf("Unable to load azure-cli profile: %v", err)
	}

	for _, s := range profile.Subscriptions {
		if s.IsDefault {
			subIDParam.setDefault(s.ID)
			tenantIDParam.setDefault(s.TenantID)
		}
	}
	return nil
}

type param struct {
	envvar, flag string
}

func paramNew(name, desc string) param {
	flag.String(name, "", desc)
	return param{
		flag:   name,
		envvar: "AZURE_" + strings.ToUpper(strings.Replace(name, "-", "_", -1)),
	}
}

func (p *param) setDefault(def string) {
	if f := flag.Lookup(p.flag); f != nil {
		f.DefValue = def
	}
}

func (p *param) get() (string, error) {
	ret := os.Getenv(p.envvar)
	if ret != "" {
		return ret, nil
	}
	if f := flag.Lookup(p.flag); f != nil {
		if f.Value.String() == "" {
			res, err := prompt(f.Usage, f.DefValue)
			if err != nil {
				return "", err
			}
			if err := f.Value.Set(res); err != nil {
				return "", err
			}
		}
		return f.Value.String(), nil
	}
	return "", fmt.Errorf("No value for %s", p.flag)
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

// As azure-cli says:
// "combining filters is unsupported, so we pick the best, and do limited maunal[sic] filtering"
func filterRoleAssignments(iter authorization.RoleAssignmentListResultIterator, principalID, roleDefID string) ([]authorization.RoleAssignment, error) {
	var ret []authorization.RoleAssignment
	log.Debugf("filterRoleAssignments(%v, %v)", roleDefID, principalID)
	for iter.NotDone() {
		ra := iter.Value()
		log.Debugf("Considering %#v", ra)
		if *ra.Properties.RoleDefinitionID == roleDefID && *ra.Properties.PrincipalID == principalID {
			log.Debug("hit!")
			ret = append(ret, ra)
		}

		if err := iter.Next(); err != nil {
			return nil, err
		}
	}
	log.Debugf("Done, returning")
	return ret, nil
}

func ensureApp(ctx context.Context, appClient graphrbac.ApplicationsClient, params graphrbac.ApplicationCreateParameters) (graphrbac.Application, error) {
	if params.IdentifierUris == nil || len(*params.IdentifierUris) != 1 {
		// The filter expression below only handles this case
		panic("ensureApp() requires len(IdentifierUris) == 1")
	}
	identifierURI := (*params.IdentifierUris)[0]

	appIter, err := appClient.ListComplete(ctx, fmt.Sprintf("identifierUris/any(s:s eq '%s')", identifierURI))
	if err != nil {
		return graphrbac.Application{}, err
	}
	if appIter.NotDone() {
		app := appIter.Value()
		log.Infof("Using existing AD application %s", *app.AppID)
		return app, nil
	}
	// no results -> create new app
	app, err := appClient.Create(ctx, params)
	if err != nil {
		return graphrbac.Application{}, err
	}
	log.Infof("Created new AD application %s", *app.AppID)
	return app, nil
}

func ensureServicePrincipal(ctx context.Context, spClient graphrbac.ServicePrincipalsClient, params graphrbac.ServicePrincipalCreateParameters) (graphrbac.ServicePrincipal, error) {
	spIter, err := spClient.ListComplete(ctx, fmt.Sprintf("appId eq '%s'", *params.AppID))
	if err != nil {
		return graphrbac.ServicePrincipal{}, err
	}
	if spIter.NotDone() {
		sp := spIter.Value()
		log.Infof("Using existing service principal %s", *sp.ObjectID)
		return sp, nil
	}
	sp, err := spClient.Create(ctx, params)
	if err != nil {
		return graphrbac.ServicePrincipal{}, err
	}
	log.Infof("Created new service principal %s", *sp.ObjectID)
	return sp, nil
}

func ensureRoleAssignment(ctx context.Context, roleClient authorization.RoleAssignmentsClient, scope string, params authorization.RoleAssignmentCreateParameters) (authorization.RoleAssignment, error) {
	roleAssigns, err := roleClient.ListComplete(ctx, fmt.Sprintf("principalId eq '%s'", *params.Properties.PrincipalID))
	if err != nil {
		return authorization.RoleAssignment{}, err
	}
	ras, err := filterRoleAssignments(roleAssigns, *params.Properties.PrincipalID, *params.Properties.RoleDefinitionID)
	if err != nil {
		return authorization.RoleAssignment{}, err
	}
	if len(ras) > 0 {
		ra := ras[0]
		log.Debugf("Using existing role assignment %s", *ra.ID)
		return ra, nil
	}

	uid, err := uuid.NewV4()
	if err != nil {
		return authorization.RoleAssignment{}, err
	}

	// Azure will throw PrincipalNotFound if used "too soon" after creation :(
	var lastErr error
	for retries := 0; retries < 30; retries++ {
		log.Debugf("Creating role assignment %s (retry %d)...", uid, retries)
		ra, lastErr := roleClient.Create(ctx, scope, uid.String(), params)

		if lastErr != nil {
			// Azure :(
			if strings.Contains(lastErr.Error(), "PrincipalNotFound") {
				log.Debugf("Azure returned %v, retrying", lastErr)
				time.Sleep(5)
				continue
			}

			return authorization.RoleAssignment{}, lastErr
		}

		log.Infof("Assigned role %s to sp %s within scope %s named %s", *params.Properties.RoleDefinitionID, *params.Properties.PrincipalID, scope, *ra.Name)
		return ra, nil
	}

	return authorization.RoleAssignment{}, lastErr
}

func base64RandBytes(n uint) (string, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(buf), nil
}

func PreUpdate(objs []*unstructured.Unstructured) ([]*unstructured.Unstructured, error) {
	ctx := context.TODO()

	env := azure.PublicCloud

	subID, err := subIDParam.get()
	if err != nil {
		return objs, err
	}

	domain, err := dnsZoneParam.get()
	if err != nil {
		return objs, err
	}

	tenantID, err := tenantIDParam.get()
	if err != nil {
		return objs, err
	}

	logInspector := LoggingInspector{Logger: log.StandardLogger()}

	authers := map[string]autorest.Authorizer{}
	configClient := func(c *autorest.Client, resource string) error {
		auther := authers[resource]
		if auther == nil {
			auther, err = authorizer(resource, tenantID)
			if err != nil {
				return err
			}
			authers[resource] = auther
		}
		c.Authorizer = auther
		if glog.V(4) {
			c.RequestInspector = logInspector.WithInspection()
			c.ResponseInspector = logInspector.ByInspecting()
		}
		if err := c.AddToUserAgent(userAgent); err != nil {
			return err
		}
		return nil
	}

	if domain != "" {
		//
		// externaldns setup
		//

		secret, err := base64RandBytes(12)
		if err != nil {
			return nil, err
		}

		dnsResgrp, err := dnsResgrpParam.get()
		if err != nil {
			return objs, err
		}

		log.Debug("About to create Azure clients")

		dnsClient := dns.NewZonesClientWithBaseURI(env.ResourceManagerEndpoint, subID)
		if err := configClient(&dnsClient.Client, env.ResourceManagerEndpoint); err != nil {
			return objs, err
		}

		zone, err := dnsClient.CreateOrUpdate(ctx, dnsResgrp, domain, dns.Zone{Location: to.StringPtr("global"), ZoneProperties: &dns.ZoneProperties{ZoneType: "Public"}}, "", "*")
		if err != nil {
			if strings.Contains(err.Error(), "PreconditionFailed") {
				log.Infof("Using existing Azure DNS zone %q", domain)
			} else {
				return objs, err
			}
		} else {
			log.Infof("Created Azure DNS zone %q", domain)
			// TODO: we could do a DNS lookup to test if this was already the case
			log.Infof("You will need to ensure glue records exist for %s pointing to NS %v", domain, *zone.NameServers)
		}

		groupsClient := resources.NewGroupsClientWithBaseURI(env.ResourceManagerEndpoint, subID)
		if err := configClient(&groupsClient.Client, env.ResourceManagerEndpoint); err != nil {
			return objs, err
		}

		// az group show --name $resgrp
		grp, err := groupsClient.Get(ctx, dnsResgrp)
		if err != nil {
			return objs, err
		}
		log.Debugf("Got grp %q -> %s", dnsResgrp, *grp.ID)

		// begin: az ad sp create-for-rbac --role=Contributor --scopes=$rgid
		log.Debugf("Creating AD service principal")

		appClient := graphrbac.NewApplicationsClientWithBaseURI(env.GraphEndpoint, tenantID)
		if err := configClient(&appClient.Client, env.GraphEndpoint); err != nil {
			return objs, err
		}

		log.Debugf("Creating AD application ...")
		app, err := ensureApp(ctx, appClient, graphrbac.ApplicationCreateParameters{
			AvailableToOtherTenants: to.BoolPtr(false),
			DisplayName:             to.StringPtr("kubeprod"),
			Homepage:                to.StringPtr("http://kubeprod.io"),
			IdentifierUris:          &[]string{fmt.Sprintf("http://%s-kubeprod-externaldns-user", domain)},
		})
		if err != nil {
			return objs, err
		}

		_, err = appClient.UpdatePasswordCredentials(ctx, *app.ObjectID, graphrbac.PasswordCredentialsUpdateParameters{
			Value: &[]graphrbac.PasswordCredential{{
				StartDate: &date.Time{Time: time.Now()},
				EndDate:   &date.Time{Time: time.Now().AddDate(10, 0, 0)}, // now + 10 years
				KeyID:     nil,
				Value:     to.StringPtr(secret),
			}},
		})
		if err != nil {
			return objs, err
		}

		spClient := graphrbac.NewServicePrincipalsClientWithBaseURI(env.GraphEndpoint, tenantID)
		if err := configClient(&spClient.Client, env.GraphEndpoint); err != nil {
			return objs, err
		}

		log.Debugf("Creating service principal...")
		sp, err := ensureServicePrincipal(ctx, spClient, graphrbac.ServicePrincipalCreateParameters{
			AppID:          app.AppID,
			AccountEnabled: to.BoolPtr(true),
		})
		if err != nil {
			return objs, err
		}

		roleDefClient := authorization.NewRoleDefinitionsClientWithBaseURI(env.ResourceManagerEndpoint, subID)
		if err := configClient(&roleDefClient.Client, env.ResourceManagerEndpoint); err != nil {
			return objs, err
		}

		roles, err := roleDefClient.List(ctx, *grp.ID, "roleName eq 'Contributor'")
		if err != nil {
			return objs, err
		}

		contribRoleID := roles.Values()[0].ID

		roleClient := authorization.NewRoleAssignmentsClientWithBaseURI(env.ResourceManagerEndpoint, subID)
		if err := configClient(&roleClient.Client, env.ResourceManagerEndpoint); err != nil {
			return objs, err
		}

		_, err = ensureRoleAssignment(ctx, roleClient, *grp.ID, authorization.RoleAssignmentCreateParameters{
			Properties: &authorization.RoleAssignmentProperties{
				PrincipalID:      sp.ObjectID,
				RoleDefinitionID: contribRoleID,
			},
		})
		if err != nil {
			return objs, err
		}

		// end: az ad sp create-for-rbac

		conf, err := json.Marshal(map[string]string{
			"tenantId":        tenantID,
			"subscriptionId":  subID,
			"aadClientId":     *app.AppID,
			"aadClientSecret": secret,
			"resourceGroup":   dnsResgrp,
		})
		if err != nil {
			return objs, err
		}

		ednsconf := &v1.Secret{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: metav1.NamespaceSystem,
				Name:      "external-dns-azure-conf",
			},
			StringData: map[string]string{
				"azure.json": string(conf),
			},
		}

		obj, err := toUnstructured(ednsconf)
		if err != nil {
			return objs, err
		}
		objs = append(objs, obj)

		//
		// oauth2-proxy setup
		//

		log.Debug("Starting oauth2-proxy setup")

		// I Quote: cookie_secret must be 16, 24, or 32 bytes
		// to create an AES cipher when pass_access_token ==
		// true or cookie_refresh != 0
		cookieSecret, err := base64RandBytes(24)
		if err != nil {
			return nil, err
		}

		clientSecret, err := base64RandBytes(18)
		if err != nil {
			return nil, err
		}

		oauthHosts := []string{"prometheus", "kibana"}
		replyUrls := make([]string, len(oauthHosts))
		for i, h := range oauthHosts {
			replyUrls[i] = fmt.Sprintf("https://%s.%s/oauth2/callback", h, domain)
		}

		// az ad app create ...
		app, err = ensureApp(ctx, appClient, graphrbac.ApplicationCreateParameters{
			AvailableToOtherTenants: to.BoolPtr(false),
			DisplayName:             to.StringPtr("Kubeprod cluster management"),
			Homepage:                to.StringPtr("http://kubeprod.io"),
			IdentifierUris:          &[]string{fmt.Sprintf("https://oauth.%s/oauth2", domain)},
			ReplyUrls:               &replyUrls,
			RequiredResourceAccess: &[]graphrbac.RequiredResourceAccess{{
				// "User.Read" for "Microsoft.Azure.ActiveDirectory"
				// aka "Sign in and read user profile"
				ResourceAppID: to.StringPtr("00000002-0000-0000-c000-000000000000"),
				ResourceAccess: &[]graphrbac.ResourceAccess{{
					ID:   to.StringPtr("311a71cc-e848-46a1-bdf8-97ff7156d8e6"),
					Type: to.StringPtr("Scope"),
				}},
			}},
		})
		if err != nil {
			return objs, err
		}

		_, err = appClient.UpdatePasswordCredentials(ctx, *app.ObjectID, graphrbac.PasswordCredentialsUpdateParameters{
			Value: &[]graphrbac.PasswordCredential{{
				StartDate: &date.Time{Time: time.Now()},
				EndDate:   &date.Time{Time: time.Now().AddDate(10, 0, 0)}, // now + 10 years
				KeyID:     nil,
				Value:     to.StringPtr(clientSecret),
			}},
		})
		if err != nil {
			return objs, err
		}

		oauthProxyConf := &v1.Secret{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: metav1.NamespaceSystem,
				Name:      "oauth2-proxy",
			},
			StringData: map[string]string{
				"client_id":     *app.AppID,
				"client_secret": clientSecret,
				"cookie_secret": cookieSecret,
				"azure_tenant":  tenantID,
			},
		}

		obj, err = toUnstructured(oauthProxyConf)
		if err != nil {
			return objs, err
		}
		objs = append(objs, obj)
	}

	return objs, nil
}

func toUnstructured(obj runtime.Object) (*unstructured.Unstructured, error) {
	buf := bytes.Buffer{}
	codec := scheme.Codecs.LegacyCodec(v1.SchemeGroupVersion)
	if err := codec.Encode(obj, &buf); err != nil {
		return nil, err
	}
	ret := unstructured.Unstructured{}
	_, _, err := unstructured.UnstructuredJSONScheme.Decode(buf.Bytes(), nil, &ret)
	return &ret, err
}
