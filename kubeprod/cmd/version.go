package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var Version = "(dev build)"

func init() {
	RootCmd.AddCommand(versionCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version information",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		out := cmd.OutOrStdout()

		fmt.Fprintf(out, "Installer Version: %s\n", Version)

		return nil
	},
}
