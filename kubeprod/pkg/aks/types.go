package aks

// Structure of `azure.json` required by external-dns
type ExternalDnsAzureConfig struct {
	TenantID        string `json:"tenantId"`
	SubscriptionID  string `json:"subscriptionId"`
	AADClientID     string `json:"aadClientId"`
	AADClientSecret string `json:"aadClientSecret"`
	ResourceGroup   string `json:"resourceGroup"`
}

// Config options required by oauth2-proxy
type OauthProxyConfig struct {
	ClientID     string `json:"client_id"`
	ClientSecret string `json:"client_secret"`
	CookieSecret string `json:"cookie_secret"`
	AzureTenant  string `json:"azure_tenant"`
}

// Local config required for AKS platforms
type AKSConfig struct {
	// TODO: Promote this to a proper (versioned) k8s Object
	DnsZone      string                 `json:"dnsZone"`
	ContactEmail string                 `json:"contactEmail"`
	ExternalDNS  ExternalDnsAzureConfig `json:"externalDns"`
	OauthProxy   OauthProxyConfig       `json:"oauthProxy"`
}
