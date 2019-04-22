KUBECFG = kubecfg

COMPONENTS := $(wildcard components/*.jsonnet)
PLATFORMS := $(wildcard tests/*.jsonnet)
UNITTESTS := $(wildcard contrib/*_test.jsonnet)

JFILES := \
  $(wildcard */*.libsonnet) \
  $(COMPONENTS) $(PLATFORMS)

validate: $(UNITTESTS:%.jsonnet=%.jsonnet-validate)
validate: $(PLATFORMS:%.jsonnet=%.jsonnet-validate)

init-submodules:
	git submodule init; \
	git submodule update --init --remote --recursive;

%.jsonnet-validate: %.jsonnet $(JFILES)
	$(KUBECFG) validate --ignore-unknown $<

.PHONY: all init-submodules validate
.PHONY: %.jsonnet-validate
