KUBECFG = kubecfg
KUBECFG_FLAGS = -V EMAIL=foo@example.com -V DNS_SUFFIX=example.com

COMPONENTS := $(wildcard components/*.jsonnet)
PLATFORMS := $(wildcard platforms/*.jsonnet)

JFILES := \
  $(wildcard */*.libsonnet) \
  $(COMPONENTS) $(PLATFORMS)

validate: $(PLATFORMS:%.jsonnet=%.jsonnet-validate)

%.jsonnet-validate: %.jsonnet $(JFILES)
	$(KUBECFG) $(KUBECFG_FLAGS) validate --ignore-unknown $<

.PHONY: all validate
.PHONY: %.jsonnet-validate
