VERSION = dev-$(shell date +%FT%T%z)

GO = go
GOFLAGS =
GOBUILDFLAGS = $(GOFLAGS) -ldflags='-X main.version=$(VERSION)'
GORELEASEFLAGS = $(GOBUILDFLAGS) -tags netgo -installsuffix netgo
GOTESTFLAGS = $(GOFLAGS) -race
GOFMT = gofmt
export CGO_ENABLED

BINDIR = bin

GOPKGS = . ./cmd/... ./pkg/...

all: $(BINDIR)/kubeprod

$(BINDIR)/kubeprod: $(shell tools/godeps.sh .)
	$(GO) build -o $@ $(GOFLAGS) $(GOBUILDFLAGS) .

release:
	$(MAKE) release/kubeprod BINDIR=release CGO_ENABLED=0 GOBUILDFLAGS="$(GORELEASEFLAGS)"

test:
	$(GO) test $(GOTESTFLAGS) $(GOPKGS)

fmt:
	$(GOFMT) -s -w $(shell $(GO) list -f '{{$$d := .Dir}}{{range .GoFiles}}{{$$d}}/{{.}} {{end}}' $(GOPKGS))

vet:
	$(GO) vet $(GOPKGS)
