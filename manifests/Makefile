KUBECFG = kubecfg -J components:lib:$(HOME)/go/src/github.com/ksonnet/kubecfg/lib

COMPONENTS := $(wildcard components/*.jsonnet)
PLATFORMS := $(wildcard platforms/*.jsonnet)

JFILES := \
  $(wildcard */*.libsonnet) \
  $(COMPONENTS) $(PLATFORMS)

all: $(PLATFORMS:%.jsonnet=%.yaml)

%.yaml: %.jsonnet $(JFILES)
	$(KUBECFG) show $< >$@.tmp
	mv $@.tmp $@

validate: $(PLATFORMS:%.jsonnet=%.jsonnet-validate)

%.jsonnet-validate: %.jsonnet $(JFILES)
	$(KUBECFG) validate $<

.PHONY: all validate
.PHONY: %.jsonnet-validate
