// Copyright 2017 The kubecfg authors
//
//
//    Licensed under the Apache License, Version 2.0 (the "License");
//    you may not use this file except in compliance with the License.
//    You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//    Unless required by applicable law or agreed to in writing, software
//    distributed under the License is distributed on an "AS IS" BASIS,
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//    See the License for the specific language governing permissions and
//    limitations under the License.

package utils

import (
	"bytes"
	"fmt"

	"github.com/genuinetools/reg/registry"
	"github.com/genuinetools/reg/repoutils"
)

const defaultRegistry = "registry-1.docker.io"	

// ImageName represents the parts of a docker image name
type ImageName struct {
	// eg: "myregistryhost:5000/fedora/httpd:version1.0"
	Registry   string // "myregistryhost:5000"
	Repository string // "fedora"
	Name       string // "httpd"
	Tag        string // "version1.0"
	Digest     string
}

// String implements the Stringer interface
func (n ImageName) String() string {
	buf := bytes.Buffer{}
	if n.Registry != "" {
		buf.WriteString(n.Registry)
		buf.WriteString("/")
	}
	if n.Repository != "" {
		buf.WriteString(n.Repository)
		buf.WriteString("/")
	}
	buf.WriteString(n.Name)
	if n.Digest != "" {
		buf.WriteString("@")
		buf.WriteString(n.Digest)
	} else {
		buf.WriteString(":")
		buf.WriteString(n.Tag)
	}
	return buf.String()
}

// RegistryRepoName returns the "repository" as used in the registry URL
func (n ImageName) RegistryRepoName() string {
	repo := n.Repository
	if repo == "" {
		repo = "library"
	}
	return fmt.Sprintf("%s/%s", repo, n.Name)
}

// RegistryURL returns the deduced base URL of the registry for this image
func (n ImageName) RegistryURL() string {
	reg := n.Registry
	if reg == "" {
		reg = defaultRegistry
	}
	return fmt.Sprintf("https://%s", reg)
}

// ParseImageName parses a docker image into an ImageName struct.
func ParseImageName(image string) (ImageName, error) {
	ret := ImageName{}

	img, err := registry.ParseImage(image)
	if err != nil {
		return ret, err
	}

	ret.Registry = img.Domain
	ret.Name = img.Path
	ret.Digest = img.Digest.String()
	ret.Tag = img.Tag

	return ret, nil
}

// Resolver is able to resolve docker image names into more specific forms
type Resolver interface {
	Resolve(image *ImageName) error
}

// NewIdentityResolver returns a resolver that does only trivial
// :latest canonicalisation
func NewIdentityResolver() Resolver {
	return identityResolver{}
}

type identityResolver struct{}

func (r identityResolver) Resolve(image *ImageName) error {
	return nil
}

// NewRegistryResolver returns a resolver that looks up a docker
// registry to resolve digests
func NewRegistryResolver(opt registry.Opt) Resolver {
	return &registryResolver{
		opt:   opt,
		cache: make(map[string]string),
	}
}

type registryResolver struct {
	opt   registry.Opt
	cache map[string]string
}

func (r *registryResolver) Resolve(n *ImageName) error {
	if n.Digest != "" {
		// Already has explicit digest
		return nil
	}

	if digest, ok := r.cache[n.String()]; ok {
		n.Digest = digest
		return nil
	}

	img, err := registry.ParseImage(n.String())
	if err != nil {
		return fmt.Errorf("unable to parse image name: %v", err)
	}

	auth, err := repoutils.GetAuthConfig("", "", img.Domain)
	if err != nil {
		return fmt.Errorf("unable to get auth config for registry: %v", err)
	}

	c, err := registry.New(auth, r.opt)
	if err != nil {
		return fmt.Errorf("unable to create registry client: %v", err)
	}

	digest, err := c.Digest(img)
	if err != nil {
		return fmt.Errorf("unable to get digest from the registry: %v", err)
	}

	n.Digest = digest.String()
	r.cache[n.String()] = n.Digest

	return nil
}
