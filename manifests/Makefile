KUBECFG = kubecfg
KUBECFG_FLAGS = -J components -J lib

COMPONENTS := $(wildcard components/*.jsonnet)
PLATFORMS := $(wildcard platforms/*.jsonnet)

JFILES := \
  $(wildcard */*.libsonnet) \
  $(COMPONENTS) $(PLATFORMS)

all: $(PLATFORMS:%.jsonnet=%.yaml)

%.yaml: %.jsonnet $(JFILES)
	$(KUBECFG) $(KUBECFG_FLAGS) show $< >$@.tmp
	mv $@.tmp $@

validate: $(PLATFORMS:%.jsonnet=%.jsonnet-validate)

%.jsonnet-validate: %.jsonnet $(JFILES)
	$(KUBECFG) $(KUBECFG_FLAGS) validate --ignore-unknown $<

.PHONY: all validate
.PHONY: %.jsonnet-validate
