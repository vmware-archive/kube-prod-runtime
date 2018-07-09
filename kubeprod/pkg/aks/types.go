package aks

// Structure of `azure.json` required by external-dns
type ExternalDnsAzureConfig struct {
	TenantID        string `json:"tenantId" mapstructure:"tenantId"`
	SubscriptionID  string `json:"subscriptionId" mapstructure:"subscriptionId"`
	AADClientID     string `json:"aadClientId" mapstructure:"aadClientId"`
	AADClientSecret string `json:"aadClientSecret" mapstructure:"aadClientSecret"`
	ResourceGroup   string `json:"resourceGroup" mapstructure:"resourceGroup"`
}

// Config options required by oauth2-proxy
type OauthProxyConfig struct {
	ClientID     string `json:"client_id" mapstructure:"client_id"`
	ClientSecret string `json:"client_secret" mapstructure:"client_secret"`
	CookieSecret string `json:"cookie_secret" mapstructure:"cookie_secret"`
	AzureTenant  string `json:"azure_tenant" mapstructure:"azure_tenant"`
}

// Local config required for AKS platforms
type AKSConfig struct {
	// TODO: Promote this to a proper (versioned) k8s Object
	DnsZone     string                 `json:"dnsZone" mapstructure:"dnsZone"`
	ExternalDNS ExternalDnsAzureConfig `json:"externalDns" mapstructure:"externalDns"`
	OauthProxy  OauthProxyConfig       `json:"oauthProxy" mapstructure:"oauthProxy"`
}
