package utils

import (
	"errors"
	"fmt"
	"io/ioutil"
	"net"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"time"

	assetfs "github.com/elazarl/go-bindata-assetfs"
	jsonnet "github.com/google/go-jsonnet"
	log "github.com/sirupsen/logrus"
)

var errNotFound = errors.New("Not found")

var extVarKindRE = regexp.MustCompile("^<(?:extvar|top-level-arg):.+>$")

//go:generate go-bindata -nometadata -ignore .*_test\.|~$DOLLAR -pkg $GOPACKAGE -o bindata.go -prefix ../ ../lib/...
func newInternalFS(prefix string) http.FileSystem {
	// Asset/AssetDir returns `fmt.Errorf("Asset %s not found")`,
	// which does _not_ get mapped to 404 by `http.FileSystem`.
	// Need to convert to `os.ErrNotExist` explicitly ourselves.
	mapNotFound := func(err error) error {
		if err != nil && strings.Contains(err.Error(), "not found") {
			err = os.ErrNotExist
		}
		return err
	}
	return &assetfs.AssetFS{
		Asset: func(path string) ([]byte, error) {
			ret, err := Asset(path)
			return ret, mapNotFound(err)
		},
		AssetDir: func(path string) ([]string, error) {
			ret, err := AssetDir(path)
			return ret, mapNotFound(err)
		},
		Prefix: prefix,
	}
}

/*
MakeUniversalImporter creates an importer that handles resolving imports from the filesystem and HTTP/S.

In addition to the standard importer, supports:
  - URLs in import statements
  - URLs in library search paths

A real-world example:
  - You have https://raw.githubusercontent.com/ksonnet/ksonnet-lib/master in your search URLs.
  - You evaluate a local file which calls `import "ksonnet.beta.2/k.libsonnet"`.
  - If the `ksonnet.beta.2/k.libsonnet`` is not located in the current working directory, an attempt
    will be made to follow the search path, i.e. to download
    https://raw.githubusercontent.com/ksonnet/ksonnet-lib/master/ksonnet.beta.2/k.libsonnet.
  - Since the downloaded `k.libsonnet`` file turn in contains `import "k8s.libsonnet"`, the import
    will be resolved as https://raw.githubusercontent.com/ksonnet/ksonnet-lib/master/ksonnet.beta.2/k8s.libsonnet
	and downloaded from that location.
*/
func MakeUniversalImporter(searchURLs []*url.URL) jsonnet.Importer {
	// Reconstructed copy of http.DefaultTransport (to avoid
	// modifying the default)
	t := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
		DialContext: (&net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
			DualStack: true,
		}).DialContext,
		MaxIdleConns:          100,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
	}

	t.RegisterProtocol("file", http.NewFileTransport(http.Dir("/")))
	t.RegisterProtocol("internal", http.NewFileTransport(newInternalFS("lib")))

	return &universalImporter{
		BaseSearchURLs: searchURLs,
		HTTPClient:     &http.Client{Transport: t},
		cache:          map[string]jsonnet.Contents{},
	}
}

type universalImporter struct {
	BaseSearchURLs []*url.URL
	HTTPClient     *http.Client
	cache          map[string]jsonnet.Contents
}

func (importer *universalImporter) Import(importedFrom, importedPath string) (jsonnet.Contents, string, error) {
	log.Debugf("Importing %q from %q", importedPath, importedFrom)

	candidateURLs, err := importer.expandImportToCandidateURLs(importedFrom, importedPath)
	if err != nil {
		return jsonnet.Contents{}, "", fmt.Errorf("Could not get candidate URLs for when importing %s (imported from %s): %v", importedPath, importedFrom, err)
	}

	var tried []string
	for _, u := range candidateURLs {
		foundAt := u.String()
		if c, ok := importer.cache[foundAt]; ok {
			return c, foundAt, nil
		}

		tried = append(tried, foundAt)
		importedData, err := importer.tryImport(foundAt)
		if err == nil {
			importer.cache[foundAt] = importedData
			return importedData, foundAt, nil
		} else if err != errNotFound {
			return jsonnet.Contents{}, "", err
		}
	}

	return jsonnet.Contents{}, "", fmt.Errorf("Couldn't open import %q, no match locally or in library search paths. Tried: %s",
		importedPath,
		strings.Join(tried, ";"),
	)
}

func (importer *universalImporter) tryImport(url string) (jsonnet.Contents, error) {
	res, err := importer.HTTPClient.Get(url)
	if err != nil {
		return jsonnet.Contents{}, err
	}
	defer res.Body.Close()
	log.Debugf("GET %q -> %s", url, res.Status)
	if res.StatusCode == http.StatusNotFound {
		return jsonnet.Contents{}, errNotFound
	} else if res.StatusCode != http.StatusOK {
		return jsonnet.Contents{}, fmt.Errorf("error reading content: %s", res.Status)
	}

	bodyBytes, err := ioutil.ReadAll(res.Body)
	if err != nil {
		return jsonnet.Contents{}, err
	}
	return jsonnet.MakeContents(string(bodyBytes)), nil
}

func (importer *universalImporter) expandImportToCandidateURLs(importedFrom, importedPath string) ([]*url.URL, error) {
	importedPathURL, err := url.Parse(importedPath)
	if err != nil {
		return nil, fmt.Errorf("Import path %q is not valid", importedPath)
	}
	if importedPathURL.IsAbs() {
		return []*url.URL{importedPathURL}, nil
	}

	importDirURL, err := url.Parse(importedFrom)
	if err != nil {
		return nil, fmt.Errorf("Invalid import dir %q: %v", importedFrom, err)
	}

	candidateURLs := make([]*url.URL, 1, len(importer.BaseSearchURLs)+1)
	candidateURLs[0] = importDirURL.ResolveReference(importedPathURL)

	for _, u := range importer.BaseSearchURLs {
		candidateURLs = append(candidateURLs, u.ResolveReference(importedPathURL))
	}

	return candidateURLs, nil
}
