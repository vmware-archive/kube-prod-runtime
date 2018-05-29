package installer

import (
	"encoding/json"
	"fmt"
	"io"
	"net/url"
	"path"

	jsonnet "github.com/google/go-jsonnet"
	"github.com/ksonnet/kubecfg/pkg/kubecfg"
	"github.com/ksonnet/kubecfg/utils"
	log "github.com/sirupsen/logrus"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/dynamic"
	restclient "k8s.io/client-go/rest"

	"github.com/bitnami/kube-prod-runtime/kubeprod/pkg/prodruntime"
)

const GcTag = "bitnami.com/prod-runtime"

// InstallCmd represents the show subcommand
type InstallCmd struct {
	Config     *restclient.Config
	ClientPool dynamic.ClientPool
	Discovery  discovery.DiscoveryInterface

	Platform     *prodruntime.Platform
	ManifestBase *url.URL
	ContactEmail string
	DnsSuffix    string
}

func (c InstallCmd) Run(out io.Writer) error {
	var err error
	log.Info("Installing platform ", c.Platform.Name)

	update := kubecfg.UpdateCmd{
		ClientPool:       c.ClientPool,
		Discovery:        c.Discovery,
		DefaultNamespace: metav1.NamespaceSystem,
		Create:           true,
		GcTag:            GcTag,
	}

	searchPaths := []string{
		"components/",
		"lib/",
		"internal:///",
	}
	searchUrls := make([]*url.URL, len(searchPaths))
	for i, p := range searchPaths {
		searchUrls[i], err = c.ManifestBase.Parse(p)
		if err != nil {
			return fmt.Errorf("unable to make URL from %q (relative to %q): %v", p, c.ManifestBase, err)
		}
	}
	importer := utils.MakeUniversalImporter(searchUrls)

	input, err := c.Platform.ManifestURL(c.ManifestBase)
	if err != nil {
		return err
	}

	extvars := map[string]string{
		"EMAIL":      c.ContactEmail,
		"DNS_SUFFIX": c.DnsSuffix,
	}
	objs, err := readObjs(importer, extvars, input)
	if err != nil {
		return err
	}

	objs, err = c.Platform.RunPreUpdate(objs)
	if err != nil {
		return err
	}

	if err := update.Run(objs); err != nil {
		return err
	}

	if err := c.Platform.RunPostUpdate(c.Config); err != nil {
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

	data, err := importer.Import(inputDir.String(), input.String())
	if err != nil {
		return "", err
	}
	return vm.EvaluateSnippet(data.FoundHere, data.Content)
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
