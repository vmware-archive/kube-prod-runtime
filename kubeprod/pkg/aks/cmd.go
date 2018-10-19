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

package aks

import (
	"os"

	azcli "github.com/Azure/go-autorest/autorest/azure/cli"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"

	kubeprodcmd "github.com/bitnami/kube-prod-runtime/kubeprod/cmd"
)

const (
	flagEmail     = "email"
	flagDNSSuffix = "dns-zone"
	flagSubID     = "subscription-id"
	flagTenantID  = "tenant-id"
	flagDNSResgrp = "dns-resource-group"
)

func defaultSubscription() *azcli.Subscription {
	path, err := azcli.ProfilePath()
	if err != nil {
		log.Debugf("Unable to find azure-cli profile: %v", err)
		return nil
	}
	profile, err := azcli.LoadProfile(path)
	if err != nil {
		log.Debugf("Unable to load azure-cli profile: %v", err)
		return nil
	}

	for _, s := range profile.Subscriptions {
		if s.IsDefault {
			return &s
		}
	}
	return nil
}

var aksCmd = &cobra.Command{
	Use:   "aks",
	Short: "Install Bitnami Production Runtime for AKS",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := kubeprodcmd.NewInstallSubcommand(cmd)
		if err != nil {
			return err
		}

		conf := AKSConfig{}
		c.PlatformConfig = &conf
		if err := c.ReadPlatformConfig(&conf); err != nil {
			return err
		}
		if err := config(cmd, &conf); err != nil {
			return err
		}
		if err := c.WritePlatformConfig(&conf); err != nil {
			return err
		}

		return c.Run(cmd.OutOrStdout())
	},
}

func init() {
	kubeprodcmd.InstallCmd.AddCommand(aksCmd)

	var defSubID, defTenantID string
	if defSub := defaultSubscription(); defSub != nil {
		defSubID = defSub.ID
		defTenantID = defSub.TenantID
	}

	aksCmd.PersistentFlags().String(flagEmail, os.Getenv("EMAIL"), "Contact email for cluster admin")

	aksCmd.PersistentFlags().String(flagSubID, defSubID, "Azure subscription ID")
	aksCmd.PersistentFlags().String(flagTenantID, defTenantID, "Azure tenant ID")
	aksCmd.PersistentFlags().String(flagDNSSuffix, "", "External DNS zone for public endpoints")
	aksCmd.PersistentFlags().String(flagDNSResgrp, "", "Resource group of external DNS zone")
}
