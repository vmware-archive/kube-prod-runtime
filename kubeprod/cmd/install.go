package cmd

import (
	"fmt"
	"net/url"
	"os"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/installer"
	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/prodruntime"
)

const (
	flagPlatform        = "platform"
	flagManifests       = "manifests"
	flagEmail           = "email"
	DefaultManifestBase = "https://github.com/bitnami/kube-prod-runtime/manifests/"
)

func init() {
	RootCmd.AddCommand(installCmd)
	installCmd.PersistentFlags().String(flagPlatform, "", "Target platform name.  See list-platforms for possible values")
	installCmd.MarkPersistentFlagRequired(flagPlatform)
	installCmd.PersistentFlags().String(flagManifests, DefaultManifestBase, "Base URL below which to find platform manifests")
	installCmd.PersistentFlags().String(flagEmail, os.Getenv("EMAIL"), "Contact email for cluster admin")
}

func cwdURL() (*url.URL, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return nil, fmt.Errorf("failed to get current working directory: %v", err)
	}
	if cwd[len(cwd)-1] != '/' {
		cwd = cwd + "/"
	}
	return &url.URL{Scheme: "file", Path: cwd}, nil
}

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install Bitnami Production Runtime for Kubernetes",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		flags := cmd.Flags()
		var err error

		c := installer.InstallCmd{}

		cwdUrl, err := cwdURL()
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
		if c.ContactEmail == "" {
			log.Warning("Email address was not provided. Some services may not function correctly.")
		}

		c.Config, err = clientConfig.ClientConfig()
		if err != nil {
			return err
		}

		c.ClientPool, c.Discovery, err = restClientPool(c.Config)

		return c.Run(cmd.OutOrStdout())
	},
}
