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

package prodruntime

import (
	"bufio"
	"fmt"
	"net/url"
	"os"
	"text/template"

	log "github.com/sirupsen/logrus"
)

const (
	clusterTemplate = `// Cluster-specific configuration
(import "{{.ManifestsURL}}") {
	config:: import "{{.ConfigFilePath}}",
	// Place your overrides here
}
`

	// RootManifest specifies the filename of the root (cluster) manifest
	RootManifest          = "kubeprod-manifest.jsonnet"
	DefaultPlatformConfig = "kubeprod-autogen.json"
)

// WriteRootManifest executes the template from the `clusterTemplate`
// variable and writes the result as the root (cluster) manifest in
// the current directory named after the value of `RootManifest`.
func WriteRootManifest(manifestsURL *url.URL) error {
	// If the output file already exists do not overwrite it.
	v := map[string]string{
		"ConfigFilePath": DefaultPlatformConfig,
		"ManifestsURL":   manifestsURL.String(),
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
