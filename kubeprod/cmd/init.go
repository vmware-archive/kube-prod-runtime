package cmd

import (
	"errors"
	"os"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/aks"
	"github.com/spf13/cobra"
)

const (
	flagKubernetesVersion      = "kubernetes-version"
	flagKubernetesVersionShort = "k"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialise Bitnami Production Runtime for Kubernetes",
	Args:  cobra.NoArgs,
}

var initAksCmd = &cobra.Command{
	Use:   "aks",
	Short: "Initialise Bitnami Production Runtime for Azure AKS",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		flags := cmd.Flags()
		clusterName, err := flags.GetString("context")
		if err != nil {
			return err
		}
		if len(clusterName) == 0 {
			return errors.New("No Kubernetes --context specified in the command-line")
		}
		manifestsBase, err := flags.GetString(flagManifests)
		if err != nil {
			return err
		}
		email, err := flags.GetString(flagEmail)
		if err != nil {
			return err
		}
		dnsZone, err := flags.GetString(flagDnsSuffix)
		if err != nil {
			return err
		}
		kubernetesVersion, err := flags.GetString(flagKubernetesVersion)
		if err != nil {
			return err
		}
		return aks.Init(clusterName, manifestsBase, email, dnsZone, kubernetesVersion)
	},
}

func init() {
	RootCmd.AddCommand(initCmd)
	initCmd.AddCommand(initAksCmd)
	initCmd.PersistentFlags().String(flagManifests, DefaultManifestBase, "Base URL below which to find platform manifests")
	initCmd.MarkPersistentFlagRequired(flagManifests)
	initCmd.PersistentFlags().String(flagEmail, os.Getenv("EMAIL"), "Contact email for Letsencrypt")
	initCmd.MarkPersistentFlagRequired(flagEmail)
	initCmd.PersistentFlags().String(flagDnsSuffix, "", "DNS zone")
	initCmd.MarkPersistentFlagRequired(flagDnsSuffix)
	initCmd.PersistentFlags().StringP(flagKubernetesVersion, flagKubernetesVersionShort, "", "Kubernetes version deployed in AKS")
	initCmd.MarkPersistentFlagRequired(flagKubernetesVersion)
}
