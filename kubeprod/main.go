package main

import (
	"fmt"
	"os"

	log "github.com/sirupsen/logrus"

	"github.com/bitnami/kube-prod-runtime/kubeprod/cmd"
)

var version = "(dev build)"

func main() {
	if err := cmd.RootCmd.Execute(); err != nil {
		// PersistentPreRunE may not have been run for early
		// errors, like invalid command line flags.
		logFmt := cmd.NewLogFormatter(log.StandardLogger().Out)
		log.SetFormatter(logFmt)
		log.Error(fmt.Sprint("Error: ", err.Error()))

		os.Exit(1)
	}
}
