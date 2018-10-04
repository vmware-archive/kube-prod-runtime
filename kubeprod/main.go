package main

import (
	"fmt"
	"os"

	log "github.com/sirupsen/logrus"

	"github.com/bitnami/kube-prod-runtime/kubeprod/cmd"

	// Register k8s auth plugins
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	// Register platform-specific packages
	_ "github.com/bitnami/kube-prod-runtime/kubeprod/pkg/aks"
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
