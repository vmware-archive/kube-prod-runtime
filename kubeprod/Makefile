VERSION ?= dev-$(shell date +%FT%T%z)
TARGETS ?= darwin/amd64 linux/amd64 windows/amd64
PACKAGE = kubeprod

GO = go
GOFLAGS =
GOBUILDFLAGS = $(GOFLAGS) -ldflags='-X main.version=$(VERSION)'
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
	@for platform in $(TARGETS); do \
		GOOS=$${platform%/*} ; \
		GOARCH=$${platform#*/} ; \
		output=_dist/$${GOOS}-$${GOARCH}/$(PACKAGE)-$${GOOS}-$${GOARCH} ; \
		if [ $${GOOS} = "windows" ]; then output=$${output}.exe ; fi ; \
		echo CGO_ENABLED=0 GOOS=$${GOOS} GOARCH=$${GOARCH} go build -o $${output} $(GORELEASEFLAGS) . ; \
		CGO_ENABLED=0 GOOS=$${GOOS} GOARCH=$${GOARCH} go build -o $${output} $(GORELEASEFLAGS) . ; \
	done

test:
	$(GO) test $(GOTESTFLAGS) $(GOPKGS)

fmt:
	$(GOFMT) -s -w $(shell $(GO) list -f '{{$$d := .Dir}}{{range .GoFiles}}{{$$d}}/{{.}} {{end}}' $(GOPKGS))

vet:
	$(GO) vet $(GOPKGS)

clean:
	rm -rf $(BINDIR)

.PHONY: all release test fmt vet clean
