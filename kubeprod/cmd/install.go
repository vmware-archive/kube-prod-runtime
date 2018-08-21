package cmd

import (
	"github.com/spf13/cobra"
)

var installCmd = &cobra.Command{
	Use:   "install",
	Short: "Install Bitnami Production Runtime for Kubernetes",
	Args:  cobra.NoArgs,
}

func init() {
	RootCmd.AddCommand(installCmd)
}
