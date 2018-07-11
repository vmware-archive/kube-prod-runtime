package aks

import (
	"bufio"
	"os"
	"path/filepath"
	"text/template"

	log "github.com/sirupsen/logrus"
)

const clusterTemplate = `
# Cluster-specific configuration

local config = import "kubeprod.json";
local aks = import "{{.ManifestsPath}}platforms/{{.Platform}}.jsonnet";

aks {
	azure_subscription:: config.ExternalDNS.SubscriptionID,
	azure_tenant:: config.TenantID,
	edns_resource_group:: config.ExternalDNS.ResourceGroup,
	edns_client_id:: config.ExternalDNS.AADClientID,
	edns_client_secret:: config.ExternalDNS.AADClientSecret,
	oauth2_client_id:: config.OauthProxy.ClientID,
	oauth2_client_secret:: config.OauthProxy.ClientSecret,
	oauth2_cookie_secret:: config.OauthProxy.CookieSecret,
	external_dns_zone_name:: config.DnsZone,
	letsencrypt_contact_email:: config.ContactEmail,
	// Place your overrides here
}
`

// Executes the template inside the `templateData` variable performing
// substitutions from the `v` dictionary and write the results to the
// output file named as `pathName`.
func WriteRootManifest(manifestsBase string, platform string) error {
	// If the output file already exists do not overwrite it.
	absPathName, err := filepath.Abs("./kube-system.jsonnet")
	if err != nil {
		return err
	}
	v := map[string]string{
		"ManifestsPath": manifestsBase,
		"Platform":      platform,
	}
	if _, err = os.Stat(absPathName); err == nil {
		log.Warning("Will not overwrite already existing output file: ", absPathName)
		return nil
	}
	f, err := os.Create(absPathName)
	if err != nil {
		return err
	}
	defer f.Close()
	w := bufio.NewWriter(f)
	defer w.Flush()
	tmpl, err := template.New("template").Parse(clusterTemplate)
	if err != nil {
		return err
	}
	return tmpl.ExecuteTemplate(w, "template", v)
}
