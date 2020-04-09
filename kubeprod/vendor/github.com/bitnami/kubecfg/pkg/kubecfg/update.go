package kubecfg

import (
	"fmt"
	"sort"
	"time"

	jsonpatch "github.com/evanphx/json-patch"
	log "github.com/sirupsen/logrus"
	apiext_v1b1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1beta1"
	apiequality "k8s.io/apimachinery/pkg/api/equality"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/util/diff"
	"k8s.io/apimachinery/pkg/util/jsonmergepatch"
	"k8s.io/apimachinery/pkg/util/sets"
	"k8s.io/apimachinery/pkg/util/strategicpatch"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/util/retry"
	"k8s.io/kube-openapi/pkg/util/proto"
	"k8s.io/kubernetes/pkg/kubectl/cmd/util/openapi"

	"github.com/bitnami/kubecfg/utils"
)

const (
	// AnnotationOrigObject annotation records the resource as it
	// was most recently specified by kubecfg (serialised to
	// JSON).  This is used as input to the strategic-merge-patch
	// 3-way merge when performing updates.
	AnnotationOrigObject = "kubecfg.ksonnet.io/last-applied-configuration"

	// AnnotationGcTag annotation that triggers
	// garbage collection. Objects with value equal to
	// command-line flag that are *not* in config will be deleted.
	//
	// NB: this is in phase1 of a migration to use a label instead.
	// At this stage, both label+migration are written, but the
	// annotation (only) is still used to trigger GC. [gctag-migration]
	AnnotationGcTag = LabelGcTag

	// LabelGcTag label that triggers garbage collection. Objects
	// with value equal to command-line flag that are *not* in
	// config will be deleted.
	//
	// NB: this is in phase1 of a migration from an annotation.
	// At this stage, both label+migration are written, but the
	// annotation (only) is still used to trigger GC. [gctag-migration]
	LabelGcTag = "kubecfg.ksonnet.io/garbage-collect-tag"

	// AnnotationGcStrategy controls gc logic.  Current values:
	// `auto` (default if absent) - do garbage collection
	// `ignore` - never garbage collect this object
	AnnotationGcStrategy = "kubecfg.ksonnet.io/garbage-collect-strategy"

	// GcStrategyAuto is the default automatic gc logic
	GcStrategyAuto = "auto"
	// GcStrategyIgnore means this object should be ignored by garbage collection
	GcStrategyIgnore = "ignore"
)

var (
	gkCRD = schema.GroupKind{Group: "apiextensions.k8s.io", Kind: "CustomResourceDefinition"}
)

// UpdateCmd represents the update subcommand
type UpdateCmd struct {
	Client           dynamic.Interface
	Mapper           meta.RESTMapper
	Discovery        discovery.DiscoveryInterface
	DefaultNamespace string

	Create bool
	GcTag  string
	SkipGc bool
	DryRun bool
}

func isValidKindSchema(schema proto.Schema) bool {
	if schema == nil {
		return false
	}
	patchMeta := strategicpatch.NewPatchMetaFromOpenAPI(schema)
	_, _, err := patchMeta.LookupPatchMetadataForStruct("metadata")
	if err != nil {
		log.Debugf("Rejecting schema due to missing 'metadata' property (encountered %q)", err)
	}
	return err == nil
}

func patch(existing, new *unstructured.Unstructured, schema proto.Schema) (*unstructured.Unstructured, error) {
	annos := existing.GetAnnotations()
	var origData []byte
	if data := annos[AnnotationOrigObject]; data != "" {
		tmp := unstructured.Unstructured{}
		err := utils.CompactDecodeObject(data, &tmp)
		if err != nil {
			return nil, err
		}
		origData, err = tmp.MarshalJSON()
		if err != nil {
			return nil, err
		}
	}

	log.Debugf("origData: %s", origData)

	new = new.DeepCopy()
	utils.DeleteMetaDataAnnotation(new, AnnotationOrigObject)
	data, err := utils.CompactEncodeObject(new)
	if err != nil {
		return nil, err
	}
	utils.SetMetaDataAnnotation(new, AnnotationOrigObject, data)

	// Note origData may be empty if last-applied annotation didn't exist

	newData, err := new.MarshalJSON()
	if err != nil {
		return nil, err
	}

	existingData, err := existing.MarshalJSON()
	if err != nil {
		return nil, err
	}

	var resData []byte
	if schema == nil {
		// No schema information - fallback to JSON merge patch
		patch, err := jsonmergepatch.CreateThreeWayJSONMergePatch(origData, newData, existingData)
		if err != nil {
			return nil, err
		}
		resData, err = jsonpatch.MergePatch(existingData, patch)
		if err != nil {
			return nil, err
		}
	} else {
		patchMeta := strategicpatch.NewPatchMetaFromOpenAPI(schema)

		patch, err := strategicpatch.CreateThreeWayMergePatch(origData, newData, existingData, patchMeta, true)
		if err != nil {
			return nil, err
		}
		resData, err = strategicpatch.StrategicMergePatchUsingLookupPatchMeta(existingData, patch, patchMeta)
		if err != nil {
			return nil, err
		}
	}

	result, _, err := unstructured.UnstructuredJSONScheme.Decode(resData, nil, nil)
	if err != nil {
		return nil, err
	}

	return result.(*unstructured.Unstructured), nil
}

func createOrUpdate(rc dynamic.ResourceInterface, obj *unstructured.Unstructured, create bool, dryRun bool, schema proto.Schema, desc, dryRunText string) (*unstructured.Unstructured, error) {
	existing, err := rc.Get(obj.GetName(), metav1.GetOptions{})
	if create && errors.IsNotFound(err) {
		log.Info("Creating ", desc, dryRunText)

		data, err := utils.CompactEncodeObject(obj)
		if err != nil {
			return nil, err
		}
		utils.SetMetaDataAnnotation(obj, AnnotationOrigObject, data)

		if dryRun {
			return obj, nil
		}
		newobj, err := rc.Create(obj, metav1.CreateOptions{})
		log.Debugf("Create(%s) returned (%v, %v)", obj.GetName(), newobj, err)
		return newobj, err
	}
	if err != nil {
		return nil, err
	}

	mergedObj, err := patch(existing, obj, schema)
	if err != nil {
		return nil, err
	}

	// Kubernetes is a bit odd when/how it reports
	// metadata.creationTimestamp.  Here, patch() gets confused by
	// the explicit creationTimestamp=null (it's not omitEmpty).
	// It's easiest here to just nuke any existing timestamp,
	// since we don't care.
	if ts := mergedObj.GetCreationTimestamp(); ts.IsZero() {
		existing.SetCreationTimestamp(metav1.Time{})
	}
	if apiequality.Semantic.DeepEqual(existing, mergedObj) {
		log.Debugf("Not updating %s - unchanged", desc)
		return mergedObj, nil
	}

	log.Debug("About to make change: ", diff.ObjectDiff(existing, mergedObj))
	log.Info("Updating ", desc, dryRunText)
	if dryRun {
		return mergedObj, nil
	}
	newobj, err := rc.Update(mergedObj, metav1.UpdateOptions{})
	log.Debugf("Update(%s) returned (%v, %v)", mergedObj.GetName(), newobj, err)
	if err != nil {
		log.Debug("Updated object: ", diff.ObjectDiff(existing, newobj))
	}
	return newobj, err
}

// CustomResourceDefinitions modify the discovery metadata, so need
// some extra help.  NB: This is also true of other things like
// APIService registrations - we don't handle those automatically yet
// (and perhaps never will in the full general case).
func isSchemaEstablished(obj *unstructured.Unstructured) bool {
	if obj.GroupVersionKind().GroupKind() != gkCRD {
		// Not a CRD
		return true
	}

	crd := apiext_v1b1.CustomResourceDefinition{}
	converter := runtime.DefaultUnstructuredConverter
	if err := converter.FromUnstructured(obj.UnstructuredContent(), &crd); err != nil {
		log.Warnf("failed to parse CustomResourceDefinition: %v", err)
		return false // retry
	}

	for _, cond := range crd.Status.Conditions {
		if cond.Type == apiext_v1b1.Established && cond.Status == apiext_v1b1.ConditionTrue {
			return true
		}
	}
	return false
}

func waitForSchemaChange(disco discovery.DiscoveryInterface, rc dynamic.ResourceInterface, obj *unstructured.Unstructured) {
	if isSchemaEstablished(obj) {
		return
	}
	log.Debugf("Waiting for schema change from %v to become established", obj.GetName())
	err := wait.Poll(100*time.Millisecond, 30*time.Minute, func() (bool, error) {
		// Re-fetch discovery metadata
		utils.MaybeMarkStale(disco)

		var err error
		obj, err = rc.Get(obj.GetName(), metav1.GetOptions{})
		if err != nil {
			if errors.IsNotFound(err) {
				// continue polling
				return false, nil
			}
			return false, err
		}

		return isSchemaEstablished(obj), nil
	})
	if err != nil {
		log.Warnf("Encountered an error while waiting for new schema change to propagate (%v).  Ignoring and continuing, which may lead to further errors.", err)
	}
}

// Run executes the update command
func (c UpdateCmd) Run(apiObjects []*unstructured.Unstructured) error {
	dryRunText := ""
	if c.DryRun {
		dryRunText = " (dry-run)"
	}

	log.Infof("Fetching schemas for %d resources", len(apiObjects))
	depOrder, err := utils.DependencyOrder(c.Discovery, c.Mapper, apiObjects)
	if err != nil {
		return err
	}
	sort.Sort(depOrder)

	seenUids := sets.NewString()

	schemaDoc, err := c.Discovery.OpenAPISchema()
	if err != nil {
		return err
	}
	schemaResources, err := openapi.NewOpenAPIData(schemaDoc)
	if err != nil {
		return err
	}

	for _, obj := range apiObjects {
		log.Debugf("Starting update of %s", utils.FqName(obj))

		if c.GcTag != "" {
			// [gctag-migration]: Remove annotation in phase2
			utils.SetMetaDataAnnotation(obj, AnnotationGcTag, c.GcTag)
			utils.SetMetaDataLabel(obj, LabelGcTag, c.GcTag)
		}

		desc := fmt.Sprintf("%s %s", utils.ResourceNameFor(c.Mapper, obj), utils.FqName(obj))

		rc, err := utils.ClientForResource(c.Client, c.Mapper, obj, c.DefaultNamespace)
		if err != nil {
			return err
		}

		schema := schemaResources.LookupResource(obj.GroupVersionKind())
		if !isValidKindSchema(schema) {
			// Invalid schema (eg: custom resource without
			// schema returns trivial type:object with k8s >=1.15)
			log.Debugf("Ignoring invalid schema for %s", obj.GroupVersionKind())
			schema = nil
		}

		var newobj *unstructured.Unstructured
		err = retry.RetryOnConflict(retry.DefaultBackoff, func() (err error) {
			newobj, err = createOrUpdate(rc, obj, c.Create, c.DryRun, schema, desc, dryRunText)
			return
		})
		if err != nil {
			return fmt.Errorf("Error updating %s: %s", desc, err)
		}

		// Some objects appear under multiple kinds
		// (eg: Deployment is both extensions/v1beta1
		// and apps/v1beta1).  UID is the only stable
		// identifier that links these two views of
		// the same object.
		seenUids.Insert(string(newobj.GetUID()))

		waitForSchemaChange(c.Discovery, rc, newobj)
	}

	if c.GcTag != "" && !c.SkipGc {
		version, err := utils.FetchVersion(c.Discovery)
		if err != nil {
			version = utils.GetDefaultVersion()
			log.Warnf("Unable to parse server version. Received %v. Using default %s", err, version.String())
		}

		// [gctag-migration]: Add LabelGcTag==c.GcTag to ListOptions.LabelSelector in phase2
		err = walkObjects(c.Client, c.Discovery, metav1.ListOptions{}, func(o runtime.Object) error {
			meta, err := meta.Accessor(o)
			if err != nil {
				return err
			}
			gvk := o.GetObjectKind().GroupVersionKind()
			desc := fmt.Sprintf("%s %s (%s)", utils.ResourceNameFor(c.Mapper, o), utils.FqName(meta), gvk.GroupVersion())
			log.Debugf("Considering %v for gc", desc)
			if eligibleForGc(meta, c.GcTag) && !seenUids.Has(string(meta.GetUID())) {
				log.Info("Garbage collecting ", desc, dryRunText)
				if !c.DryRun {
					err := gcDelete(c.Client, c.Mapper, &version, o)
					if err != nil {
						return err
					}
				}
			}
			return nil
		})
		if err != nil {
			return err
		}
	}

	return nil
}

func stringListContains(list []string, value string) bool {
	for _, item := range list {
		if item == value {
			return true
		}
	}
	return false
}

func gcDelete(client dynamic.Interface, mapper meta.RESTMapper, version *utils.ServerVersion, o runtime.Object) error {
	obj, err := meta.Accessor(o)
	if err != nil {
		return fmt.Errorf("Unexpected object type: %s", err)
	}

	uid := obj.GetUID()
	desc := fmt.Sprintf("%s %s", utils.ResourceNameFor(mapper, o), utils.FqName(obj))

	deleteOpts := metav1.DeleteOptions{
		Preconditions: &metav1.Preconditions{UID: &uid},
	}
	if version.Compare(1, 6) < 0 {
		// 1.5.x option
		boolFalse := false
		deleteOpts.OrphanDependents = &boolFalse
	} else {
		// 1.6.x option (NB: Background is broken)
		fg := metav1.DeletePropagationForeground
		deleteOpts.PropagationPolicy = &fg
	}

	c, err := utils.ClientForResource(client, mapper, o, metav1.NamespaceNone)
	if err != nil {
		return err
	}

	err = c.Delete(obj.GetName(), &deleteOpts)
	if err != nil && (errors.IsNotFound(err) || errors.IsConflict(err)) {
		// We lost a race with something else changing the object
		log.Debugf("Ignoring error while deleting %s: %s", desc, err)
		err = nil
	}
	if err != nil {
		return fmt.Errorf("Error deleting %s: %s", desc, err)
	}

	return nil
}

func walkObjects(client dynamic.Interface, disco discovery.DiscoveryInterface, listopts metav1.ListOptions, callback func(runtime.Object) error) error {
	rsrclists, err := disco.ServerResources()
	if err != nil {
		return err
	}
	for _, rsrclist := range rsrclists {
		gv, err := schema.ParseGroupVersion(rsrclist.GroupVersion)
		if err != nil {
			return err
		}

		for _, rsrc := range rsrclist.APIResources {
			if !stringListContains(rsrc.Verbs, "list") {
				log.Debugf("Don't know how to list %#v, skipping", rsrc)
				continue
			}

			gvr := gv.WithResource(rsrc.Name)
			if rsrc.Group != "" {
				gvr.Group = rsrc.Group
			}
			if rsrc.Version != "" {
				gvr.Version = rsrc.Version
			}

			var rc dynamic.ResourceInterface
			if rsrc.Namespaced {
				rc = client.Resource(gvr).Namespace(metav1.NamespaceAll)
			} else {
				rc = client.Resource(gvr)
			}

			log.Debugf("Listing %s", gvr)
			obj, err := rc.List(listopts)
			if err != nil {
				return err
			}
			if err = meta.EachListItem(obj, callback); err != nil {
				return err
			}
		}
	}
	return nil
}

func eligibleForGc(obj metav1.Object, gcTag string) bool {
	for _, ref := range obj.GetOwnerReferences() {
		if ref.Controller != nil && *ref.Controller {
			// Has a controller ref
			return false
		}
	}

	a := obj.GetAnnotations()

	strategy, ok := a[AnnotationGcStrategy]
	if !ok {
		strategy = GcStrategyAuto
	}

	// [gctag-migration]: Check *label* == tag instead in phase2
	return a[AnnotationGcTag] == gcTag &&
		strategy == GcStrategyAuto
}
