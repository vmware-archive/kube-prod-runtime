/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2020 Bitnami
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

package generic

import (
	"os"

	"github.com/spf13/cobra"

	kubeprodcmd "github.com/bitnami/kube-prod-runtime/kubeprod/cmd"
)

const (
	flagEmail            = "email"
	flagDNSSuffix        = "dns-zone"
	flagAuthzDomain      = "authz-domain"
	flagKeycloakPassword = "keycloak-password"
	flagKeycloakGroup    = "keycloak-group"
)

var genericCmd = &cobra.Command{
	Use:   "generic",
	Short: "Install Bitnami Production Runtime for Generic Kubernetes cluster",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := kubeprodcmd.NewInstallSubcommand(cmd, "generic", &GenericConfig{flags: cmd.Flags()})
		if err != nil {
			return err
		}
		return c.Run(cmd.OutOrStdout())
	},
}

func init() {
	kubeprodcmd.InstallCmd.AddCommand(genericCmd)

	genericCmd.PersistentFlags().String(flagEmail, os.Getenv("EMAIL"), "Contact email for cluster admin")
	genericCmd.PersistentFlags().String(flagDNSSuffix, "", "External DNS zone for public endpoints")
	genericCmd.PersistentFlags().String(flagAuthzDomain, "", "Restrict authorized users to this Google email domain")
	genericCmd.PersistentFlags().String(flagKeycloakGroup, "", "Restrict authorized users to this Keycloak group")
	genericCmd.PersistentFlags().String(flagKeycloakPassword, "", "Password for Keycloak admin user")
	genericCmd.MarkPersistentFlagRequired(flagAuthzDomain)
	genericCmd.MarkPersistentFlagRequired(flagKeycloakGroup)
	genericCmd.MarkPersistentFlagRequired(flagKeycloakPassword)
}
