package utils

import (
	"compress/gzip"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	log "github.com/sirupsen/logrus"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/version"
	"k8s.io/client-go/discovery"
)

// Format v0.0.0(-master+$Format:%h$)
var gitVersionRe = regexp.MustCompile("v([0-9])+.([0-9])+.[0-9]+.*")

// ServerVersion captures k8s major.minor version in a parsed form
type ServerVersion struct {
	Major int
	Minor int
}

func parseGitVersion(gitVersion string) (ServerVersion, error) {
	parsedVersion := gitVersionRe.FindStringSubmatch(gitVersion)
	if len(parsedVersion) != 3 {
		return ServerVersion{}, fmt.Errorf("Unable to parse git version %s", gitVersion)
	}
	var ret ServerVersion
	var err error
	ret.Major, err = strconv.Atoi(parsedVersion[1])
	if err != nil {
		return ServerVersion{}, err
	}
	ret.Minor, err = strconv.Atoi(parsedVersion[2])
	if err != nil {
		return ServerVersion{}, err
	}
	return ret, nil
}

// ParseVersion parses version.Info into a ServerVersion struct
func ParseVersion(v *version.Info) (ServerVersion, error) {
	var ret ServerVersion
	var err error
	ret.Major, err = strconv.Atoi(v.Major)
	if err != nil {
		// Try to parse using GitVersion
		return parseGitVersion(v.GitVersion)
	}

	// trim "+" in minor version (happened on GKE)
	v.Minor = strings.TrimSuffix(v.Minor, "+")
	ret.Minor, err = strconv.Atoi(v.Minor)
	if err != nil {
		// Try to parse using GitVersion
		return parseGitVersion(v.GitVersion)
	}
	return ret, err
}

// FetchVersion fetches version information from discovery client, and parses
func FetchVersion(v discovery.ServerVersionInterface) (ret ServerVersion, err error) {
	version, err := v.ServerVersion()
	if err != nil {
		return ServerVersion{}, err
	}
	return ParseVersion(version)
}

// GetDefaultVersion returns a default server version. This value will be updated
// periodically to match a current/popular version corresponding to the age of this code
// Current default version: 1.8
func GetDefaultVersion() ServerVersion {
	return ServerVersion{Major: 1, Minor: 8}
}

// Compare returns -1/0/+1 iff v is less than / equal / greater than major.minor
func (v ServerVersion) Compare(major, minor int) int {
	a := v.Major
	b := major

	if a == b {
		a = v.Minor
		b = minor
	}

	var res int
	if a > b {
		res = 1
	} else if a == b {
		res = 0
	} else {
		res = -1
	}
	return res
}

func (v ServerVersion) String() string {
	return fmt.Sprintf("%d.%d", v.Major, v.Minor)
}

// SetMetaDataAnnotation sets an annotation value
func SetMetaDataAnnotation(obj metav1.Object, key, value string) {
	a := obj.GetAnnotations()
	if a == nil {
		a = make(map[string]string)
	}
	a[key] = value
	obj.SetAnnotations(a)
}

// DeleteMetaDataAnnotation removes an annotation value
func DeleteMetaDataAnnotation(obj metav1.Object, key string) {
	a := obj.GetAnnotations()
	if a != nil {
		delete(a, key)
		obj.SetAnnotations(a)
	}
}

// SetMetaDataLabel sets an annotation value
func SetMetaDataLabel(obj metav1.Object, key, value string) {
	l := obj.GetLabels()
	if l == nil {
		l = make(map[string]string)
	}
	l[key] = value
	obj.SetLabels(l)
}

// DeleteMetaDataLabel removes a label value
func DeleteMetaDataLabel(obj metav1.Object, key string) {
	l := obj.GetLabels()
	if l != nil {
		delete(l, key)
		obj.SetLabels(l)
	}
}

// ResourceNameFor returns a lowercase plural form of a type, for
// human messages.  Returns lowercased kind if discovery lookup fails.
func ResourceNameFor(mapper meta.RESTMapper, o runtime.Object) string {
	gvk := o.GetObjectKind().GroupVersionKind()
	mapping, err := mapper.RESTMapping(gvk.GroupKind(), gvk.Version)
	if err != nil {
		log.Debugf("RESTMapper failed for %s (%s), falling back to kind", gvk, err)
		return strings.ToLower(gvk.Kind)
	}

	return mapping.Resource.Resource
}

// FqName returns "namespace.name"
func FqName(o metav1.Object) string {
	if o.GetNamespace() == "" {
		return o.GetName()
	}
	return fmt.Sprintf("%s.%s", o.GetNamespace(), o.GetName())
}

// CompactEncodeObject returns a compact string representation
// (json->gzip->base64) of an object, intended for use in
// last-applied-configuration annotation.
func CompactEncodeObject(o runtime.Object) (string, error) {
	var buf strings.Builder
	b64enc := base64.NewEncoder(base64.StdEncoding, &buf)
	zw := gzip.NewWriter(b64enc)
	jsenc := json.NewEncoder(zw)
	jsenc.SetEscapeHTML(false)
	jsenc.SetIndent("", "")

	if err := jsenc.Encode(o); err != nil {
		return "", err
	}

	zw.Close()
	b64enc.Close()

	return buf.String(), nil
}

// CompactDecodeObject does the reverse of CompactEncodeObject.
func CompactDecodeObject(data string, into runtime.Object) error {
	zr, err := gzip.NewReader(
		base64.NewDecoder(base64.StdEncoding,
			strings.NewReader(data)))
	if err != nil {
		return err
	}

	jsdec := json.NewDecoder(zr)
	return jsdec.Decode(into)
}
