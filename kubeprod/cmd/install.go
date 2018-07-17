package cmd

import (
	"fmt"
	"os"
	"regexp"

	"github.com/spf13/cobra"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/installer"
	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/prodruntime"
)

const (
	flagPlatform        = "platform"
	flagManifests       = "manifests"
	flagEmail           = "email"
	flagDnsSuffix       = "dns-zone" // This is really pkg/aks.dnsZoneParam
	DefaultManifestBase = "https://github.com/bitnami/kube-prod-runtime/manifests/"
)

func init() {
	RootCmd.AddCommand(installCmd)
	installCmd.PersistentFlags().String(flagPlatform, "", "Target platform name.  See list-platforms for possible values")
	installCmd.MarkPersistentFlagRequired(flagPlatform)
	installCmd.PersistentFlags().String(flagManifests, DefaultManifestBase, "Base URL below which to find platform manifests")
	installCmd.PersistentFlags().String(flagEmail, os.Getenv("EMAIL"), "Contact email for cluster admin")
	installCmd.MarkPersistentFlagRequired(flagEmail)
}

func validateContacteEmail(contactEmail string) error {
	emailRegexp := regexp.MustCompile("^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$")
	if !emailRegexp.MatchString(contactEmail) {
		return fmt.Errorf("Invalid contact e-mail address: %s", contactEmail)
	}
	return nil
}

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install Bitnami Production Runtime for Kubernetes",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		flags := cmd.Flags()
		var err error

		c := installer.InstallCmd{}
		manifestBase, err := flags.GetString(flagManifests)
		if err != nil {
			return err
		}
		if len(manifestBase) > 0 && manifestBase[len(manifestBase)-1] != '/' {
			manifestBase = manifestBase + "/"
		}
		c.ManifestsPath = manifestBase
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
		if err := validateContacteEmail(c.ContactEmail); err != nil {
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
