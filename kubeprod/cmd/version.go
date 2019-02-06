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

package cmd

import (
	"fmt"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	corev1 "k8s.io/client-go/kubernetes/typed/core/v1"
)

// NB: These are overridden by main()
var Version = "(dev build)"

const (
	ReleaseNamespace = "kubeprod"
	ReleaseName      = "release"
)

func init() {
	RootCmd.AddCommand(versionCmd)
}

type Release struct {
	Release string `json:"release"`
}

func getRelease(c corev1.ConfigMapsGetter) string {
	configmap, err := c.ConfigMaps(ReleaseNamespace).Get(ReleaseName, metav1.GetOptions{})
	switch {
	case errors.IsNotFound(err):
		return "not installed"
	case err != nil:
		log.Debugf("error fetching release configmap: %v", err)
		return "unknown"
	default:
		return configmap.Data["release"]
	}
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version information",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		release := ""
		out := cmd.OutOrStdout()

		config, err := clientConfig.ClientConfig()
		if err != nil {
			release = "(unable to read kubectl config)"
		} else {
			clientv1, err := corev1.NewForConfig(config)
			if err != nil {
				return err
			}

			release = getRelease(clientv1)
			if err != nil {
				return err
			}
		}

		fmt.Fprintf(out, "Installer version: %s\n", Version)
		fmt.Fprintf(out, "Server manifests version: %s\n", release)

		return nil
	},
}
