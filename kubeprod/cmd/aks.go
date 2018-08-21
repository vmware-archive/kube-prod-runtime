package cmd

import (
	"fmt"
	"os"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/installer"
	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/prodruntime"
	"github.com/bitnami/kube-prod-runtime/kubeprod/tools"
	"github.com/spf13/cobra"
)

const (
	flagPlatform        = "platform"
	flagManifests       = "manifests"
	flagEmail           = "email"
	flagDnsSuffix       = "dns-zone" // This is really pkg/aks.dnsZoneParam
	DefaultManifestBase = "https://github.com/bitnami/kube-prod-runtime/manifests/"
)

var installAksCmd = &cobra.Command{
	Use:   "aks",
	Short: "Install Bitnami Production Runtime for AKS",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		flags := cmd.Flags()
		var err error

		c := installer.InstallCmd{}

		cwdUrl, err := tools.CwdURL()
		if err != nil {
			return err
		}
		manifestBase, err := flags.GetString(flagManifests)
		if err != nil {
			return err
		}
		if len(manifestBase) > 0 && manifestBase[len(manifestBase)-1] != '/' {
			manifestBase = manifestBase + "/"
		}
		c.ManifestBase, err = cwdUrl.Parse(manifestBase)
		if err != nil {
			return err
		}

		platform, err := flags.GetString(flagPlatform)
		if err != nil {
			return err
		}
		c.Platform = prodruntime.FindPlatform(platform)
		if c.Platform == nil {
			// TODO: add some more helpful advice about how to
			// find valid values, etc
			return fmt.Errorf("unknown platform %q", platform)
		}

		c.ContactEmail, err = flags.GetString(flagEmail)
		if err != nil {
			return err
		}
		c.DnsSuffix, err = flags.GetString(flagDnsSuffix)
		if err != nil {
			return err
		}
		if c.DnsSuffix == "" {
			return fmt.Errorf("DNS suffix was not provided.")
		}

		c.Config, err = clientConfig.ClientConfig()
		if err != nil {
			return err
		}

		c.ClientPool, c.Discovery, err = restClientPool(c.Config)

		return c.Run(cmd.OutOrStdout())
	},
}

func init() {
	installCmd.AddCommand(installAksCmd)
	installAksCmd.PersistentFlags().String(flagPlatform, "", "Target platform name.  See list-platforms for possible values")
	installAksCmd.MarkPersistentFlagRequired(flagPlatform)
	installAksCmd.PersistentFlags().String(flagManifests, DefaultManifestBase, "Base URL below which to find platform manifests")
	installAksCmd.PersistentFlags().String(flagEmail, os.Getenv("EMAIL"), "Contact email for cluster admin")
}
