package prodruntime

import (
	"bufio"
	"fmt"
	"os"
	"text/template"

	log "github.com/sirupsen/logrus"
)

const (
	clusterTemplate = `# Cluster-specific configuration
(import "{{.ManifestsPath}}platforms/{{.Platform}}.jsonnet") {
	config:: import "{{.ConfigFilePath}}",
	// Place your overrides here
}`

	// RootManifest specifies the filename of the root (cluster) manifest
	RootManifest = "kubeprod.jsonnet"
)

// WriteRootManifest executes the template from the `clusterTemplate`
// variable and writes the result as the root (cluster) manifest in
// the current directory named `kubeprod.jsonnet`
func WriteRootManifest(manifestsBase string, platform string) error {
	// If the output file already exists do not overwrite it.
	v := map[string]string{
		"ConfigFilePath": "kubeprod.json",
		"ManifestsPath":  manifestsBase,
		"Platform":       platform,
	}
	f, err := os.OpenFile(RootManifest, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0777)
	if err != nil {
		if os.IsExist(err) {
			log.Warning("Will not overwrite already existing output file: ", RootManifest)
		} else {
			return fmt.Errorf("unable to write to %q: %v", RootManifest, err)
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
