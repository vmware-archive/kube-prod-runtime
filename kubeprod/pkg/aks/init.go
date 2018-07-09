package aks

import (
	"bufio"
	"html/template"
	"os"
	"path"
)

const (
	clusterTemplate = `# Cluster-specific configuration

local config = import "config.json";
local aks = import "{{.ManifestsPath}}/platforms/aks+k8s-{{.KubernetesVersion}}.jsonnet";

aks + config {
	// Place your overrides here
}
`
	configTemplate = `{
	"cluster": "{{.ClusterName}}",
	"external_dns_zone_name": "{{.DNS}}",
	"letsencrypt_contact_email": "{{.Email}}"
}
`
)

type variables struct {
	ClusterName       string
	ManifestsPath     string // path to the manifests/ directory (including trailing /)
	Email             string // contact e-mail for Letsencrypt certificates
	DNS               string // DNS domain
	KubernetesVersion string // Kubernetes version
}

// Executes the template inside the `templateData` variable performing
// substitutions from the `v` dictionary and write the results to the
// output file named as `pathName`.
func writeTemplate(pathName string, templateData string, v variables) error {
	var f *os.File
	f, err := os.Create(pathName)
	if err != nil {
		return err
	}
	defer f.Close()
	w := bufio.NewWriter(f)
	defer w.Flush()
	tmpl, err := template.New("template").Parse(templateData)
	err = tmpl.ExecuteTemplate(w, "template", v)
	return err
}

// Init does init
func Init(clusterName string, manifestsBase string, email string, dnsZone string, kubernetesVersion string) (err error) {

	v := variables{
		ClusterName:       clusterName,
		ManifestsPath:     path.Clean(manifestsBase),
		Email:             email,
		DNS:               dnsZone,
		KubernetesVersion: kubernetesVersion,
	}

	err = writeTemplate("./"+clusterName+".json", clusterTemplate, v)
	if err != nil {
		return
	}
	err = writeTemplate("./config.json", configTemplate, v)
	if err != nil {
		return
	}
	return
}
