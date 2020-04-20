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

// Changes:
// * Merged updates from https://github.com/kubernetes/client-go/blob/kubernetes-1.18.1/discovery/cached/memory/memcache.go
//   --jjo, 2020-04-09

package utils

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"sync"
	"syscall"

	openapi_v2 "github.com/googleapis/gnostic/OpenAPIv2"

	log "github.com/sirupsen/logrus"
	errorsutil "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/apimachinery/pkg/version"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/dynamic"
	restclient "k8s.io/client-go/rest"
)

type cacheEntry struct {
	resourceList *metav1.APIResourceList
	err          error
}

// memcachedDiscoveryClient can Invalidate() to stay up-to-date with discovery
// information.
//
// TODO: Switch to a watch interface. Right now it will poll after each
// Invalidate() call.
type memcachedDiscoveryClient struct {
	delegate discovery.DiscoveryInterface

	lock                   sync.RWMutex
	groupToServerResources map[string]*cacheEntry
	groupList              *metav1.APIGroupList
	cacheValid             bool
}

// Error Constants
var (
	ErrCacheNotFound = errors.New("not found")
)

var _ discovery.CachedDiscoveryInterface = &memcachedDiscoveryClient{}

// isTransientConnectionError checks whether given error is "Connection refused" or
// "Connection reset" error which usually means that apiserver is temporarily
// unavailable.
func isTransientConnectionError(err error) bool {
	urlError, ok := err.(*url.Error)
	if !ok {
		return false
	}
	opError, ok := urlError.Err.(*net.OpError)
	if !ok {
		return false
	}
	errno, ok := opError.Err.(syscall.Errno)
	if !ok {
		return false
	}
	return errno == syscall.ECONNREFUSED || errno == syscall.ECONNRESET
}

func isTransientError(err error) bool {
	if isTransientConnectionError(err) {
		return true
	}

	if t, ok := err.(errorsutil.APIStatus); ok && t.Status().Code >= 500 {
		return true
	}

	return errorsutil.IsTooManyRequests(err)
}

// ServerResourcesForGroupVersion returns the supported resources for a group and version.
func (d *memcachedDiscoveryClient) ServerResourcesForGroupVersion(groupVersion string) (*metav1.APIResourceList, error) {
	d.lock.Lock()
	defer d.lock.Unlock()
	if !d.cacheValid {
		if err := d.refreshLocked(); err != nil {
			return nil, err
		}
	}
	cachedVal, ok := d.groupToServerResources[groupVersion]
	if !ok {
		return nil, ErrCacheNotFound
	}

	if cachedVal.err != nil && isTransientError(cachedVal.err) {
		r, err := d.serverResourcesForGroupVersion(groupVersion)
		if err != nil {
			utilruntime.HandleError(fmt.Errorf("couldn't get resource list for %v: %v", groupVersion, err))
		}
		cachedVal = &cacheEntry{r, err}
		d.groupToServerResources[groupVersion] = cachedVal
	}

	return cachedVal.resourceList, cachedVal.err
}

// ServerResources returns the supported resources for all groups and versions.
// Deprecated: use ServerGroupsAndResources instead.
func (d *memcachedDiscoveryClient) ServerResources() ([]*metav1.APIResourceList, error) {
	return discovery.ServerResources(d)
}

// ServerGroupsAndResources returns the groups and supported resources for all groups and versions.
func (d *memcachedDiscoveryClient) ServerGroupsAndResources() ([]*metav1.APIGroup, []*metav1.APIResourceList, error) {
	return discovery.ServerGroupsAndResources(d)
}

func (d *memcachedDiscoveryClient) ServerGroups() (*metav1.APIGroupList, error) {
	d.lock.Lock()
	defer d.lock.Unlock()
	if !d.cacheValid {
		if err := d.refreshLocked(); err != nil {
			return nil, err
		}
	}
	return d.groupList, nil
}

func (d *memcachedDiscoveryClient) RESTClient() restclient.Interface {
	return d.delegate.RESTClient()
}

func (d *memcachedDiscoveryClient) ServerPreferredResources() ([]*metav1.APIResourceList, error) {
	return discovery.ServerPreferredResources(d)
}

func (d *memcachedDiscoveryClient) ServerPreferredNamespacedResources() ([]*metav1.APIResourceList, error) {
	return discovery.ServerPreferredNamespacedResources(d)
}

func (d *memcachedDiscoveryClient) ServerVersion() (*version.Info, error) {
	return d.delegate.ServerVersion()
}

func (d *memcachedDiscoveryClient) OpenAPISchema() (*openapi_v2.Document, error) {
	return d.delegate.OpenAPISchema()
}

func (d *memcachedDiscoveryClient) Fresh() bool {
	d.lock.RLock()
	defer d.lock.RUnlock()
	// Return whether the cache is populated at all. It is still possible that
	// a single entry is missing due to transient errors and the attempt to read
	// that entry will trigger retry.
	return d.cacheValid
}

// Invalidate enforces that no cached data that is older than the current time
// is used.
func (d *memcachedDiscoveryClient) Invalidate() {
	d.lock.Lock()
	defer d.lock.Unlock()
	d.cacheValid = false
	d.groupToServerResources = nil
	d.groupList = nil
}

// refreshLocked refreshes the state of cache. The caller must hold d.lock for
// writing.
func (d *memcachedDiscoveryClient) refreshLocked() error {
	// TODO: Could this multiplicative set of calls be replaced by a single call
	// to ServerResources? If it's possible for more than one resulting
	// APIResourceList to have the same GroupVersion, the lists would need merged.
	gl, err := d.delegate.ServerGroups()
	if err != nil || len(gl.Groups) == 0 {
		utilruntime.HandleError(fmt.Errorf("couldn't get current server API group list: %v", err))
		return err
	}

	wg := &sync.WaitGroup{}
	resultLock := &sync.Mutex{}
	rl := map[string]*cacheEntry{}
	for _, g := range gl.Groups {
		for _, v := range g.Versions {
			gv := v.GroupVersion
			wg.Add(1)
			go func() {
				defer wg.Done()
				defer utilruntime.HandleCrash()

				r, err := d.serverResourcesForGroupVersion(gv)
				if err != nil {
					utilruntime.HandleError(fmt.Errorf("couldn't get resource list for %v: %v", gv, err))
				}

				resultLock.Lock()
				defer resultLock.Unlock()
				rl[gv] = &cacheEntry{r, err}
			}()
		}
	}
	wg.Wait()

	d.groupToServerResources, d.groupList = rl, gl
	d.cacheValid = true
	return nil
}

func (d *memcachedDiscoveryClient) serverResourcesForGroupVersion(groupVersion string) (*metav1.APIResourceList, error) {
	r, err := d.delegate.ServerResourcesForGroupVersion(groupVersion)
	if err != nil {
		return r, err
	}
	if len(r.APIResources) == 0 {
		return r, fmt.Errorf("Got empty response for: %v", groupVersion)
	}
	return r, nil
}

var _ discovery.CachedDiscoveryInterface = &memcachedDiscoveryClient{}

// MaybeMarkStale calls MarkStale on the discovery client, if the
// client is a memcachedClient.
func MaybeMarkStale(d discovery.DiscoveryInterface) {
	if c, ok := d.(*memcachedDiscoveryClient); ok {
		c.Invalidate()
	}
}

func (c *memcachedDiscoveryClient) MarkStale() {
	c.lock.Lock()
	defer c.lock.Unlock()

	log.Debug("Marking cached discovery info (potentially) stale")
	c.cacheValid = false
}

// ClientForResource returns the ResourceClient for a given object
func ClientForResource(client dynamic.Interface, mapper meta.RESTMapper, obj runtime.Object, defNs string) (dynamic.ResourceInterface, error) {
	gvk := obj.GetObjectKind().GroupVersionKind()

	mapping, err := mapper.RESTMapping(gvk.GroupKind(), gvk.Version)
	if err != nil {
		return nil, err
	}

	rc := client.Resource(mapping.Resource)

	switch mapping.Scope.Name() {
	case meta.RESTScopeNameRoot:
		return rc, nil
	case meta.RESTScopeNameNamespace:
		meta, err := meta.Accessor(obj)
		if err != nil {
			return nil, err
		}
		namespace := meta.GetNamespace()
		if namespace == "" {
			namespace = defNs
		}
		return rc.Namespace(namespace), nil
	default:
		return nil, fmt.Errorf("unexpected resource scope %q", mapping.Scope)
	}
}

// NewmemcachedDiscoveryClient creates a new CachedDiscoveryInterface which caches
// discovery information in memory and will stay up-to-date if Invalidate is
// called with regularity.
//
// NOTE: The client will NOT resort to live lookups on cache misses.
func NewMemcachedDiscoveryClient(delegate discovery.DiscoveryInterface) discovery.CachedDiscoveryInterface {
	return &memcachedDiscoveryClient{
		delegate:               delegate,
		groupToServerResources: map[string]*cacheEntry{},
	}
}
