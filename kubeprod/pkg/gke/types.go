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

package gke

import (
	flag "github.com/spf13/pflag"
)

// Structure of `azure.json` required by external-dns
type ExternalDnsConfig struct {
	// contents of GOOGLE_APPLICATION_CREDENTIALS file
	Credentials string `json:"credentials"`
	// GCP project containing dns zone
	Project string `json:"project"`
}

// Config options required by oauth2-proxy
type OauthProxyConfig struct {
	ClientID                 string   `json:"client_id"`
	ClientSecret             string   `json:"client_secret"`
	CookieSecret             string   `json:"cookie_secret"`
	AuthzDomain              string   `json:"authz_domain"`
	GoogleGroups             []string `json:"google_groups"`
	GoogleAdminEmail         string   `json:"google_admin_email"`
	GoogleServiceAccountJson string   `json:"google_service_account_json"`
}

// Local config required for GKE platforms
type GKEConfig struct {
	flags *flag.FlagSet

	// TODO: Promote this to a proper (versioned) k8s Object
	DnsZone      string            `json:"dnsZone"`
	ContactEmail string            `json:"contactEmail"`
	ExternalDNS  ExternalDnsConfig `json:"externalDns"`
	OauthProxy   OauthProxyConfig  `json:"oauthProxy"`
}
