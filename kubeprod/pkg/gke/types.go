package gke

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
	GoogleGroups             []string `json:"google_groups"`
	GoogleAdminEmail         string   `json:"google_admin_email"`
	GoogleServiceAccountJson string   `json:"google_service_account_json"`
}

// Local config required for GKE platforms
type GKEConfig struct {
	// TODO: Promote this to a proper (versioned) k8s Object
	DnsZone      string            `json:"dnsZone"`
	ContactEmail string            `json:"contactEmail"`
	ExternalDNS  ExternalDnsConfig `json:"externalDns"`
	OauthProxy   OauthProxyConfig  `json:"oauthProxy"`
}
