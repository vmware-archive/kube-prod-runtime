VERSION ?= dev-$(shell date +%FT%T%z)
DIST_DIRS = lib components platforms

KUBECFG = kubecfg

COMPONENTS := $(wildcard components/*.jsonnet)
PLATFORMS := $(wildcard tests/*.jsonnet)

JFILES := \
  $(wildcard */*.libsonnet) \
  $(COMPONENTS) $(PLATFORMS)

GO = go

validate: $(PLATFORMS:%.jsonnet=%.jsonnet-validate)

%.jsonnet-validate: %.jsonnet $(JFILES)
	$(KUBECFG) validate --ignore-unknown $<

dist: archiver
	mkdir -p _dist/manifests/
	cp -a $(DIST_DIRS) _dist/manifests/
	cp -a ../LICENSE _dist/manifests/
	cp -a ../README.md _dist/manifests/
	archiver make _dist/manifests-$(VERSION).tar.gz _dist/manifests
	archiver make _dist/manifests-$(VERSION).zip _dist/manifests

checksum:
	for f in $$(ls _dist/*.gz _dist/*.zip) ; \
  do shasum -a 256 "$${f}" | awk '{print $$1}' > $${f}.sha256 ; \
  done

HAS_ARCHIVER := $(shell command -v archiver;)

archiver:
ifndef HAS_ARCHIVER
	$(GO) get github.com/mholt/archiver/cmd/archiver
endif

clean:
	rm -rf ./_dist

.PHONY: all validate
.PHONY: %.jsonnet-validate
