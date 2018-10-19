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
	"strings"

	"github.com/spf13/cobra"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/installer"
	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/prodruntime"
	"github.com/bitnami/kube-prod-runtime/kubeprod/tools"
)

const (
	FlagPlatform = "platform"

	FlagManifests       = "manifests"
	DefaultManifestBase = "https://github.com/bitnami/kube-prod-runtime/manifests/"

	FlagPlatformConfig = "config"
)

var InstallCmd = &cobra.Command{
	Use:   "install",
	Short: "Install Bitnami Production Runtime for Kubernetes",
	Args:  cobra.NoArgs,
}

func init() {
	RootCmd.AddCommand(InstallCmd)

	InstallCmd.PersistentFlags().String(FlagPlatform, "", "Target platform name.  See list-platforms for possible values")
	InstallCmd.MarkPersistentFlagRequired(FlagPlatform)
	InstallCmd.PersistentFlags().String(FlagManifests, DefaultManifestBase, "Base URL below which to find platform manifests")
	InstallCmd.PersistentFlags().String(FlagPlatformConfig, prodruntime.DefaultPlatformConfig, "Path for generated platform config file")
}

// Common initialisation for platform install subcommands
func NewInstallSubcommand(cmd *cobra.Command) (*installer.InstallCmd, error) {
	flags := cmd.Flags()
	var err error

	c := installer.InstallCmd{}

	cwdURL, err := tools.CwdURL()
	if err != nil {
		return nil, err
	}
	manifestBase, err := flags.GetString(FlagManifests)
	if err != nil {
		return nil, err
	}
	if !strings.HasSuffix(manifestBase, "/") {
		manifestBase = manifestBase + "/"
	}
	c.ManifestBase, err = cwdURL.Parse(manifestBase)
	if err != nil {
		return nil, err
	}

	platformConfigFlag, err := flags.GetString(FlagPlatformConfig)
	if err != nil {
		return nil, err
	}
	platformConfigURL, err := cwdURL.Parse(platformConfigFlag)
	if err != nil {
		return nil, err
	}
	if platformConfigURL.Scheme != "file" {
		return nil, fmt.Errorf("platform config path must be a file:// URL")
	}
	c.PlatformConfigPath = platformConfigURL.Path

	platform, err := flags.GetString(FlagPlatform)
	if err != nil {
		return nil, err
	}
	c.Platform = prodruntime.FindPlatform(platform)
	if c.Platform == nil {
		// TODO: add some more helpful advice about how to
		// find valid values, etc
		return nil, fmt.Errorf("unknown platform %q", platform)
	}

	c.Config, err = clientConfig.ClientConfig()
	if err != nil {
		return nil, err
	}

	c.ClientPool, c.Discovery, err = restClientPool(c.Config)
	if err != nil {
		return nil, err
	}

	return &c, nil
}
