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
