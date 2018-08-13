package tools

import (
	"fmt"
	"net/url"
	"os"
)

func CwdURL() (*url.URL, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return nil, fmt.Errorf("failed to get current working directory: %v", err)
	}
	if cwd[len(cwd)-1] != '/' {
		cwd = cwd + "/"
	}
	return &url.URL{Scheme: "file", Path: cwd}, nil
}
