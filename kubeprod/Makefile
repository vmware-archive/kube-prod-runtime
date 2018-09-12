VERSION = dev-$(shell date +%FT%T%z)

GO = go
GOX = gox
GOFLAGS =
GOBUILDFLAGS = $(GOFLAGS) -ldflags='-X main.version=$(VERSION)'
GORELEASEFLAGS = $(GOBUILDFLAGS) -tags netgo
GOTESTFLAGS = $(GOFLAGS) -race
GOFMT = gofmt
export CGO_ENABLED

BINDIR = bin

GOPKGS = . ./cmd/... ./pkg/...

all: $(BINDIR)/kubeprod

$(BINDIR)/kubeprod: $(shell tools/godeps.sh .)
	$(GO) build -o $@ $(GOFLAGS) $(GOBUILDFLAGS) .

release: gox
	$(GOX) -os="darwin linux windows" -arch="amd64" \
		--output="release/kubeprod-{{.OS}}-{{.Arch}}" \
		$(GORELEASEFLAGS) .

test:
	$(GO) test $(GOTESTFLAGS) $(GOPKGS)

fmt:
	$(GOFMT) -s -w $(shell $(GO) list -f '{{$$d := .Dir}}{{range .GoFiles}}{{$$d}}/{{.}} {{end}}' $(GOPKGS))

vet:
	$(GO) vet $(GOPKGS)

HAS_GOX := $(shell command -v gox;)

gox:
ifndef HAS_GOX
	$(GO) get -u github.com/mitchellh/gox
endif

.PHONY: all release test fmt vet gox
