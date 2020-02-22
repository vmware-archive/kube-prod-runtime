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

package main

import (
	"fmt"
	"os"

	log "github.com/sirupsen/logrus"

	"github.com/bitnami/kube-prod-runtime/kubeprod/cmd"

	// Register k8s auth plugins
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	// Register platform-specific packages
	_ "github.com/bitnami/kube-prod-runtime/kubeprod/pkg/aks"
	_ "github.com/bitnami/kube-prod-runtime/kubeprod/pkg/eks"
	_ "github.com/bitnami/kube-prod-runtime/kubeprod/pkg/gke"
	_ "github.com/bitnami/kube-prod-runtime/kubeprod/pkg/generic"
)

// Overridden at link time by Makefile.
var version = ""
var releasesBaseURL = ""

func init() {
	if version != "" {
		cmd.Version = version
	}
	if releasesBaseURL != "" {
		cmd.ReleasesBaseUrl = releasesBaseURL
	}
}

func main() {
	// Update flag defaults now that all init() have completed
	cmd.UpdateFlagDefaults()

	if err := cmd.RootCmd.Execute(); err != nil {
		// PersistentPreRunE may not have been run for early
		// errors, like invalid command line flags.
		logFmt := cmd.NewLogFormatter(log.StandardLogger().Out)
		log.SetFormatter(logFmt)
		log.Error(fmt.Sprint("Error: ", err.Error()))

		os.Exit(1)
	}
}
