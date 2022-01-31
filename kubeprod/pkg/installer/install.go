/*
 * Bitnami Kubernetes Production Runtime - A collection of services that makes it
 * easy to run production workloads in Kubernetes.
 *
 * Copyright 2018-2019 Bitnami
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package installer

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/url"
	"os"
	"path"
	goruntime "runtime"

	"github.com/bitnami/kubecfg/pkg/kubecfg"
	"github.com/bitnami/kubecfg/utils"
	jsonnet "github.com/google/go-jsonnet"
	log "github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/dynamic"
	restclient "k8s.io/client-go/rest"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/prodruntime"
	"github.com/bitnami/kube-prod-runtime/kubeprod/tools"
)

const GcTag = "kube_prod_runtime"

func unmarshalFile(path string, into interface{}) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	buf, err := ioutil.ReadAll(f)
	if err != nil {
		return err
	}

	return json.Unmarshal(buf, into)
}

func marshalFile(path string, obj interface{}) error {
	buf, err := json.MarshalIndent(obj, "", "  ")
	if err != nil {
		return err
	}

	f, err := os.Create(path)
	if err != nil {
		return err
	}

	if _, err := f.Write(buf); err != nil {
		return err
	}

	return f.Close()
}

type PlatformConfig interface {
	Generate(context.Context) error
}

// InstallCmd represents the install subcommand
type InstallCmd struct {
	Config             *restclient.Config
	Client             dynamic.Interface
	Mapper             meta.RESTMapper
	Discovery          discovery.DiscoveryInterface
	OnlyGenerate       bool
	PlatformConfig     PlatformConfig
	Platform           string
	PlatformConfigPath string
	ManifestBase       *url.URL
}

// Run runs the installer
func (c InstallCmd) Run(out io.Writer) error {
	var err error
	log.Info("Installing platform ", c.Platform)
	ctx := context.TODO()

	if err := c.ReadPlatformConfig(c.PlatformConfig); err != nil {
		return err
	}
	if err := c.PlatformConfig.Generate(ctx); err != nil {
		return err
	}
	if err := c.WritePlatformConfig(c.PlatformConfig); err != nil {
		return err
	}

	manifestURL, err := c.ManifestBase.Parse(fmt.Sprintf("platforms/%s.jsonnet", c.Platform))
	if err != nil {
		return fmt.Errorf("unable to construct manifest URL: %v", err)
	}

	log.Infof("Using manifests from %s", manifestURL)
	if err := prodruntime.WriteRootManifest(manifestURL); err != nil {
		return err
	}

	if c.OnlyGenerate {
		fmt.Println("Skipping deployment because --only-generate was provided.")
	} else {
		log.Info("Deploying Bitnami Kubernetes Production Runtime for platform ", c.Platform)
		if err := c.Update(out); err != nil {
			return err
		}
	}
	return nil
}

func (c InstallCmd) ReadPlatformConfig(into interface{}) error {
	path := c.PlatformConfigPath

	if err := unmarshalFile(path, into); err == nil {
		log.Debugf("Reading existing cluster settings from %q", path)
	} else if !os.IsNotExist(err) {
		return err
	}

	return nil
}

func (c InstallCmd) WritePlatformConfig(conf interface{}) error {
	path := c.PlatformConfigPath

	if err := marshalFile(path, conf); err == nil {
		log.Infof("Writing cluster settings to %q", path)
	}

	return nil
}

func (c InstallCmd) Update(out io.Writer) error {
	log.Info("Updating platform ", c.Platform)
	searchUrls := []*url.URL{
		{Scheme: "internal", Path: "/"},
	}
	importer := utils.MakeUniversalImporter(searchUrls)
	cwdURL, err := tools.CwdURL()
	if err != nil {
		return err
	}
	input, err := cwdURL.Parse(prodruntime.RootManifest)
	if err != nil {
		return err
	}
	if goruntime.GOOS == "windows" {
		input.Path = input.Path[1:]
	}


	validate := kubecfg.ValidateCmd{
		Mapper:        c.Mapper,
		Discovery:     c.Discovery,
		IgnoreUnknown: true,
	}

	update := kubecfg.UpdateCmd{
		Client:           c.Client,
		Mapper:           c.Mapper,
		Discovery:        c.Discovery,
		DefaultNamespace: metav1.NamespaceSystem,
		Create:           true,
		GcTag:            GcTag,
	}

	extvars := map[string]string{}
	objs, err := readObjs(importer, extvars, input)
	if err != nil {
		return err
	}
	log.Info("Using root manifest ", input)
	if err := validate.Run(objs, out); err != nil {
		return err
	}
	if err := update.Run(objs); err != nil {
		return err
	}

	return nil
}

func evaluateJsonnet(importer jsonnet.Importer, extvars map[string]string, input *url.URL) (string, error) {
	vm := jsonnet.MakeVM()
	vm.Importer(importer)
	utils.RegisterNativeFuncs(vm, utils.NewIdentityResolver())

	inputDir := *input // copy
	dir, _ := path.Split(input.Path)
	inputDir.Path = dir

	for k, v := range extvars {
		vm.ExtVar(k, v)
	}

	contents, foundAt, err := importer.Import(inputDir.String(), input.String())
	if err != nil {
		return "", err
	}
	return vm.EvaluateSnippet(foundAt, contents.String())
}

func jsonToObjects(jsobjs []interface{}) ([]runtime.Object, error) {
	ret := make([]runtime.Object, 0, len(jsobjs))
	for _, v := range jsobjs {
		data, err := json.Marshal(v)
		if err != nil {
			// It came from json, so this should never happen...
			panic(fmt.Sprintf("Error marshalling json: %v", err))
		}
		obj, _, err := unstructured.UnstructuredJSONScheme.Decode(data, nil, nil)
		if err != nil {
			return nil, fmt.Errorf("error parsing kubernetes object from JSON: %v", err)
		}
		ret = append(ret, obj)
	}

	return ret, nil
}

func jsonWalk(obj interface{}) ([]interface{}, error) {
	switch o := obj.(type) {
	case map[string]interface{}:
		if o["kind"] != nil && o["apiVersion"] != nil {
			return []interface{}{o}, nil
		}
		ret := []interface{}{}
		for _, v := range o {
			children, err := jsonWalk(v)
			if err != nil {
				return nil, err
			}
			ret = append(ret, children...)
		}
		return ret, nil
	case []interface{}:
		ret := make([]interface{}, 0, len(o))
		for _, v := range o {
			children, err := jsonWalk(v)
			if err != nil {
				return nil, err
			}
			ret = append(ret, children...)
		}
		return ret, nil
	default:
		return nil, fmt.Errorf("unexpected JSON object structure: %T", o)
	}
}

// TODO: refactor kubecfg's `readObjs()`, so we can share this code
// with less omg-my-eyes.
func readObjs(importer jsonnet.Importer, extvars map[string]string, input *url.URL) ([]*unstructured.Unstructured, error) {
	jsonstr, err := evaluateJsonnet(importer, extvars, input)
	if err != nil {
		return nil, err
	}
	log.Debug("jsonnet result is: ", jsonstr)

	var top interface{}
	if err = json.Unmarshal([]byte(jsonstr), &top); err != nil {
		panic(fmt.Sprintf("jsonnet bug: produced invalid json: %v", err))
	}

	jsobjs, err := jsonWalk(top)
	if err != nil {
		return nil, err
	}

	objs, err := jsonToObjects(jsobjs)
	if err != nil {
		return nil, err
	}

	return utils.FlattenToV1(objs), nil
}
