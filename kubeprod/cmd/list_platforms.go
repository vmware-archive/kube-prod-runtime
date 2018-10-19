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

package cmd

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/prodruntime"
)

func init() {
	RootCmd.AddCommand(listPlatformsCmd)
}

var listPlatformsCmd = &cobra.Command{
	Use:   "list-platforms",
	Short: "List supported platforms",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		out := cmd.OutOrStdout()

		fmt.Fprintf(out, "Supported platforms:\n")

		for _, p := range prodruntime.Platforms {
			fmt.Fprintf(out, "\n")
			fmt.Fprintf(out, " --platform=%s\n", p.Name)
			fmt.Fprintf(out, " %s\n", p.Description)
		}

		return nil
	},
}
