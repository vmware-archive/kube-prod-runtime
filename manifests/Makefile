KUBECFG = kubecfg

COMPONENTS := $(wildcard components/*.jsonnet)
PLATFORMS := $(wildcard tests/*.jsonnet)

JFILES := \
  $(wildcard */*.libsonnet) \
  $(COMPONENTS) $(PLATFORMS)

validate: $(PLATFORMS:%.jsonnet=%.jsonnet-validate)

%.jsonnet-validate: %.jsonnet $(JFILES)
	$(KUBECFG) validate --ignore-unknown $<

.PHONY: all validate
.PHONY: %.jsonnet-validate
