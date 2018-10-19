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

package aks

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/services/authorization/mgmt/2015-07-01/authorization"
	"github.com/Azure/azure-sdk-for-go/services/dns/mgmt/2018-03-01-preview/dns"
	"github.com/Azure/azure-sdk-for-go/services/graphrbac/1.6/graphrbac"
	"github.com/Azure/azure-sdk-for-go/services/resources/mgmt/2018-02-01/resources"
	"github.com/Azure/go-autorest/autorest"
	"github.com/Azure/go-autorest/autorest/azure"
	"github.com/Azure/go-autorest/autorest/date"
	"github.com/Azure/go-autorest/autorest/to"
	"github.com/golang/glog"
	"github.com/satori/go.uuid"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/prodruntime"
	"github.com/bitnami/kube-prod-runtime/kubeprod/tools"
)

const (
	userAgent = "Bitnami/kubeprod" // TODO: version
)

func init() {
	var platforms = []prodruntime.Platform{
		{
			Name:        "aks+k8s-1.9",
			Description: "Azure Container Service (AKS) with Kubernetes 1.9",
		},
		{
			Name:        "aks+k8s-1.8",
			Description: "Azure Container Service (AKS) with Kubernetes 1.8",
		},
	}

	prodruntime.Platforms = append(prodruntime.Platforms, platforms...)
}

func createRoleAssignment(ctx context.Context, roleClient authorization.RoleAssignmentsClient, scope string, params authorization.RoleAssignmentCreateParameters) (authorization.RoleAssignment, error) {
	uid, err := uuid.NewV4()
	if err != nil {
		return authorization.RoleAssignment{}, err
	}

	const maxTries = 30

	// Azure will throw PrincipalNotFound if used "too soon" after creation :(
	for retries := 0; ; retries++ {
		log.Debugf("Creating role assignment %s (retry %d)...", uid, retries)

		ra, err := roleClient.Create(ctx, scope, uid.String(), params)
		if err != nil {
			// Azure :(
			if strings.Contains(err.Error(), "PrincipalNotFound") && retries < maxTries {
				log.Debugf("Azure returned %v, retrying", err)
				time.Sleep(1)
				continue
			}

			return authorization.RoleAssignment{}, err
		}

		log.Infof("Assigned role %s to sp %s within scope %s named %s", *params.Properties.RoleDefinitionID, *params.Properties.PrincipalID, scope, *ra.Name)
		return ra, nil
	}
}

func config(cmd *cobra.Command, conf *AKSConfig) error {
	ctx := context.TODO()
	flags := cmd.Flags()

	// Leaks secrets to log!
	//log.Debugf("Input config: %#v", conf)

	env := azure.PublicCloud

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

	logInspector := LoggingInspector{Logger: log.StandardLogger()}

	authers := map[string]autorest.Authorizer{}
	configClient := func(c *autorest.Client, tenantID, resource string) error {
		auther := authers[resource]
		if auther == nil {
			var err error
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

	if conf.DnsZone != "" {
		//
		// externaldns setup
		//

		if conf.ExternalDNS.TenantID == "" {
			tenantID, err := flags.GetString(flagTenantID)
			if err != nil {
				return err
			}
			conf.ExternalDNS.TenantID = tenantID
		}

		if conf.ExternalDNS.SubscriptionID == "" {
			subID, err := flags.GetString(flagSubID)
			if err != nil {
				return err
			}
			conf.ExternalDNS.SubscriptionID = subID
		}

		if conf.ExternalDNS.AADClientSecret == "" {
			secret, err := tools.Base64RandBytes(12)
			if err != nil {
				return err
			}
			conf.ExternalDNS.AADClientSecret = secret
		}

		if conf.ExternalDNS.ResourceGroup == "" {
			// TODO: default to Azure resource group of AKS cluster.
			// See https://docs.microsoft.com/en-us/azure/aks/faq#why-are-two-resource-groups-created-with-aks
			dnsResgrp, err := flags.GetString(flagDNSResgrp)
			if err != nil {
				return err
			}
			conf.ExternalDNS.ResourceGroup = dnsResgrp
		}

		log.Debug("About to create Azure clients")

		dnsClient := dns.NewZonesClientWithBaseURI(env.ResourceManagerEndpoint, conf.ExternalDNS.SubscriptionID)
		if err := configClient(&dnsClient.Client, conf.ExternalDNS.TenantID, env.ResourceManagerEndpoint); err != nil {
			return err
		}

		zone, err := dnsClient.CreateOrUpdate(ctx, conf.ExternalDNS.ResourceGroup, conf.DnsZone, dns.Zone{Location: to.StringPtr("global"), ZoneProperties: &dns.ZoneProperties{ZoneType: "Public"}}, "", "*")
		if err != nil {
			if strings.Contains(err.Error(), "PreconditionFailed") {
				log.Infof("Using existing Azure DNS zone %q", conf.DnsZone)
			} else {
				return err
			}
		} else {
			log.Infof("Created Azure DNS zone %q", conf.DnsZone)
			// TODO: we could do a DNS lookup to test if this was already the case
			log.Infof("You will need to ensure glue records exist for %s pointing to NS %v", conf.DnsZone, *zone.NameServers)
		}

		if conf.ExternalDNS.AADClientID == "" {
			groupsClient := resources.NewGroupsClientWithBaseURI(env.ResourceManagerEndpoint, conf.ExternalDNS.SubscriptionID)
			if err := configClient(&groupsClient.Client, conf.ExternalDNS.TenantID, env.ResourceManagerEndpoint); err != nil {
				return err
			}

			// az group show --name $resgrp
			grp, err := groupsClient.Get(ctx, conf.ExternalDNS.ResourceGroup)
			if err != nil {
				return err
			}
			log.Debugf("Got grp %q -> %s", conf.ExternalDNS.ResourceGroup, *grp.ID)

			// begin: az ad sp create-for-rbac --role=Contributor --scopes=$rgid
			log.Debugf("Creating AD service principal")

			appClient := graphrbac.NewApplicationsClientWithBaseURI(env.GraphEndpoint, conf.ExternalDNS.TenantID)
			if err := configClient(&appClient.Client, conf.ExternalDNS.TenantID, env.GraphEndpoint); err != nil {
				return err
			}

			log.Debugf("Creating AD application ...")
			app, err := appClient.Create(ctx, graphrbac.ApplicationCreateParameters{
				AvailableToOtherTenants: to.BoolPtr(false),
				DisplayName:             to.StringPtr(fmt.Sprintf("Kubeprod External DNS support for %s", conf.DnsZone)),
				Homepage:                to.StringPtr("http://kubeprod.io"),
				IdentifierUris:          &[]string{fmt.Sprintf("http://%s-kubeprod-externaldns-user", conf.DnsZone)},
			})
			if err != nil {
				return err
			}

			_, err = appClient.UpdatePasswordCredentials(ctx, *app.ObjectID, graphrbac.PasswordCredentialsUpdateParameters{
				Value: &[]graphrbac.PasswordCredential{{
					StartDate: &date.Time{Time: time.Now()},
					EndDate:   &date.Time{Time: time.Now().AddDate(10, 0, 0)}, // now + 10 years
					KeyID:     nil,
					Value:     to.StringPtr(conf.ExternalDNS.AADClientSecret),
				}},
			})
			if err != nil {
				return err
			}

			spClient := graphrbac.NewServicePrincipalsClientWithBaseURI(env.GraphEndpoint, conf.ExternalDNS.TenantID)
			if err := configClient(&spClient.Client, conf.ExternalDNS.TenantID, env.GraphEndpoint); err != nil {
				return err
			}

			log.Debugf("Creating service principal...")
			sp, err := spClient.Create(ctx, graphrbac.ServicePrincipalCreateParameters{
				AppID:          app.AppID,
				AccountEnabled: to.BoolPtr(true),
			})
			if err != nil {
				return err
			}

			roleDefClient := authorization.NewRoleDefinitionsClientWithBaseURI(env.ResourceManagerEndpoint, conf.ExternalDNS.SubscriptionID)
			if err := configClient(&roleDefClient.Client, conf.ExternalDNS.TenantID, env.ResourceManagerEndpoint); err != nil {
				return err
			}

			roles, err := roleDefClient.List(ctx, *grp.ID, "roleName eq 'Contributor'")
			if err != nil {
				return err
			}
			if len(roles.Values()) < 1 {
				return fmt.Errorf("No 'Contributor' role in resource group %q", conf.ExternalDNS.ResourceGroup)
			}
			contribRoleID := roles.Values()[0].ID

			roleClient := authorization.NewRoleAssignmentsClientWithBaseURI(env.ResourceManagerEndpoint, conf.ExternalDNS.SubscriptionID)
			if err := configClient(&roleClient.Client, conf.ExternalDNS.TenantID, env.ResourceManagerEndpoint); err != nil {
				return err
			}

			_, err = createRoleAssignment(ctx, roleClient, *grp.ID, authorization.RoleAssignmentCreateParameters{
				Properties: &authorization.RoleAssignmentProperties{
					PrincipalID:      sp.ObjectID,
					RoleDefinitionID: contribRoleID,
				},
			})
			if err != nil {
				return err
			}
			// end: az ad sp create-for-rbac

			conf.ExternalDNS.AADClientID = *app.AppID
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

	if conf.OauthProxy.ClientSecret == "" {
		secret, err := tools.Base64RandBytes(18)
		if err != nil {
			return err
		}
		conf.OauthProxy.ClientSecret = secret
	}

	if conf.OauthProxy.AzureTenant == "" {
		tenantID, err := flags.GetString(flagTenantID)
		if err != nil {
			return err
		}
		conf.OauthProxy.AzureTenant = tenantID
	}

	if conf.OauthProxy.ClientID == "" {
		appClient := graphrbac.NewApplicationsClientWithBaseURI(env.GraphEndpoint, conf.OauthProxy.AzureTenant)
		if err := configClient(&appClient.Client, conf.OauthProxy.AzureTenant, env.GraphEndpoint); err != nil {
			return err
		}

		oauthHosts := []string{"prometheus", "kibana"}
		replyUrls := make([]string, len(oauthHosts))
		for i, h := range oauthHosts {
			replyUrls[i] = fmt.Sprintf("https://%s.%s/oauth2/callback", h, conf.DnsZone)
		}

		// az ad app create ...
		app, err := appClient.Create(ctx, graphrbac.ApplicationCreateParameters{
			AvailableToOtherTenants: to.BoolPtr(false),
			DisplayName:             to.StringPtr(fmt.Sprintf("Kubeprod cluster management for %s", conf.DnsZone)),
			Homepage:                to.StringPtr("http://kubeprod.io"),
			IdentifierUris:          &[]string{fmt.Sprintf("https://oauth.%s/oauth2", conf.DnsZone)},
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
			return err
		}

		_, err = appClient.UpdatePasswordCredentials(ctx, *app.ObjectID, graphrbac.PasswordCredentialsUpdateParameters{
			Value: &[]graphrbac.PasswordCredential{{
				StartDate: &date.Time{Time: time.Now()},
				EndDate:   &date.Time{Time: time.Now().AddDate(10, 0, 0)}, // now + 10 years
				KeyID:     nil,
				Value:     to.StringPtr(conf.OauthProxy.ClientSecret),
			}},
		})
		if err != nil {
			return err
		}

		conf.OauthProxy.ClientID = *app.AppID
	}

	return nil
}
