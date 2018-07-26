package aks

import (
	"bufio"
	"os"
	"text/template"

	log "github.com/sirupsen/logrus"
)

const clusterTemplate = `# Cluster-specific configuration

(import "{{.ManifestsPath}}platforms/{{.Platform}}.jsonnet") {
	aksConfig:: import "{{.AksConfig}}",
	// Place your overrides here
}
`

// WriteRootManifest executes the template from the `clusterTemplate`
// variable and writes the result as the root (cluster) manifest in
// the current directory named `kube-system.jsonnet`
func WriteRootManifest(manifestsBase string, platform string) error {
	// If the output file already exists do not overwrite it.
	v := map[string]string{
		"AksConfig":     AksConfigFile,
		"ManifestsPath": manifestsBase,
		"Platform":      platform,
	}
	if _, err := os.Stat(AksRootManifest); err == nil {
		log.Warning("Will not overwrite already existing output file: ", AksRootManifest)
		return nil
	}
	f, err := os.Create(AksRootManifest)
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
