package aks

import (
	"bufio"
	"fmt"
	"os"
	"syscall"
	"text/template"

	log "github.com/sirupsen/logrus"
)

const clusterTemplate = `# Cluster-specific configuration

(import "{{.ManifestsPath}}platforms/{{.Platform}}.jsonnet") {
	config:: import "{{.AksConfig}}",
	// Place your overrides here
}
`

// WriteRootManifest executes the template from the `clusterTemplate`
// variable and writes the result as the root (cluster) manifest in
// the current directory named `kube-system.jsonnet`
func WriteRootManifest(manifestsBase string, platform string) error {
	// If the output file already exists do not overwrite it.
	v := map[string]string{
		"AksConfig":     "./kubeprod.json",
		"ManifestsPath": manifestsBase,
		"Platform":      platform,
	}
	f, err := os.OpenFile(AksRootManifest, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0777)
	if err != nil {
		if e, ok := err.(*os.PathError); ok && e.Err == syscall.EEXIST {
			log.Warning("Will not overwrite already existing output file: ", AksRootManifest)
		} else {
			return fmt.Errorf("unable to write to %q: %v", AksRootManifest, err)
		}
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
