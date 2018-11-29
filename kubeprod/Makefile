VERSION ?= $(shell git rev-parse --short HEAD)
RELEASES_BASE_URL ?=
TARGETS ?= darwin/amd64 linux/amd64 windows/amd64
MANIFEST_DIST_DIRS = lib components platforms

PACKAGE = kubeprod

GO = go
GOFLAGS =
GOBUILDFLAGS = $(GOFLAGS) -ldflags='-X main.version=$(VERSION) -X main.releasesBaseUrl=$(RELEASES_BASE_URL)'
GORELEASEFLAGS = $(GOBUILDFLAGS) -tags netgo -installsuffix netgo
GOTESTFLAGS = $(GOFLAGS) -race
GOFMT = gofmt
export CGO_ENABLED

BINDIR = bin

GOPKGS = . ./cmd/... ./pkg/...

all: $(BINDIR)/$(PACKAGE)

$(BINDIR)/$(PACKAGE): $(shell tools/godeps.sh .)
	$(GO) build -o $@ $(GOFLAGS) $(GOBUILDFLAGS) .

release: clean
	@set -e ; \
	for platform in $(TARGETS); do \
		GOOS=$${platform%/*} ; \
		GOARCH=$${platform#*/} ; \
		ARTIFACTS_DIR=_dist/$${GOOS}-$${GOARCH}/bkpr-$(VERSION) ; \
		outfile=$(PACKAGE) ; \
		if [ $${GOOS} = "windows" ]; then outfile=$${outfile}.exe ; fi ; \
		echo "CGO_ENABLED=0 GOOS=$${GOOS} GOARCH=$${GOARCH} go build -o $${ARTIFACTS_DIR}/$${outfile} $(GORELEASEFLAGS) ." ; \
		CGO_ENABLED=0 GOOS=$${GOOS} GOARCH=$${GOARCH} go build -o $${ARTIFACTS_DIR}/$${outfile} $(GORELEASEFLAGS) . ; \
	done

manifests: release
	@set -e ; \
	mkdir -p _dist/manifests/ ; \
	echo $(VERSION) > _dist/manifests/VERSION ; \
	for d in $(MANIFEST_DIST_DIRS); do \
		cp -a ../manifests/$${d} _dist/manifests/ ; \
	done ; \
	for platform in $(TARGETS); do \
		GOOS=$${platform%/*} ; \
		GOARCH=$${platform#*/} ; \
		ARTIFACTS_DIR=_dist/$${GOOS}-$${GOARCH}/bkpr-$(VERSION) ; \
		cp -a _dist/manifests $${ARTIFACTS_DIR}/ ; \
	done

dist: archiver release manifests
	@set -e ; \
	for platform in $(TARGETS); do \
		GOOS=$${platform%/*} ; \
		GOARCH=$${platform#*/} ; \
		ARTIFACTS_DIR=_dist/$${GOOS}-$${GOARCH}/bkpr-$(VERSION) ; \
		case $${GOOS} in \
			windows) OUTPUT_FORMAT=zip ;; \
			      *) OUTPUT_FORMAT=tar.gz ;; \
		esac ; \
		RELEASE_TARBALL=_dist/bkpr-$(VERSION)-$${GOOS}-$${GOARCH}.$${OUTPUT_FORMAT} ; \
		echo "cp -a ../LICENSE ../README.md $${ARTIFACTS_DIR}/" ; \
		cp -a ../LICENSE ../README.md $${ARTIFACTS_DIR}/ ; \
		echo "arc archive $${RELEASE_TARBALL} $${ARTIFACTS_DIR}" ; \
		arc archive $${RELEASE_TARBALL} $${ARTIFACTS_DIR} ; \
	done

checksum:
	for f in $$(ls _dist/*.gz _dist/*.zip) ; do shasum -a 256 "$${f}" | awk '{print $$1}' > $${f}.sha256 ; done

test:
	$(GO) test $(GOTESTFLAGS) $(GOPKGS)

fmt:
	$(GOFMT) -s -w $(shell $(GO) list -f '{{$$d := .Dir}}{{range .GoFiles}}{{$$d}}/{{.}} {{end}}' $(GOPKGS))

vet:
	$(GO) vet $(GOPKGS)

HAS_ARCHIVER := $(shell command -v arc;)

archiver:
ifndef HAS_ARCHIVER
	$(GO) get github.com/mholt/archiver/cmd/arc
endif

clean:
	rm -rf $(BINDIR) ./_dist

.PHONY: all release dist checksum test fmt vet archiver clean
