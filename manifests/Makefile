KUBECFG = kubecfg
JSONNET_FMT = jsonnetfmt

FMTFLAGS = \
	--indent 2 \
	--string-style d \
	--comment-style s \
	--no-pad-arrays \
	--no-pad-objects \
	--pretty-field-names \
	--max-blank-lines 2 \
	--sort-imports

COMPONENTS := $(wildcard components/*.jsonnet)
PLATFORMS := $(wildcard tests/*.jsonnet)
UNITTESTS := $(wildcard contrib/*_test.jsonnet)

JFILES := \
  $(wildcard */*.libsonnet) \
  $(COMPONENTS) $(PLATFORMS)

validate: $(UNITTESTS:%.jsonnet=%.jsonnet-validate)
validate: $(PLATFORMS:%.jsonnet=%.jsonnet-validate)

%.jsonnet-validate: %.jsonnet $(JFILES)
	$(KUBECFG) validate --ignore-unknown $<

fmt: $(JFILES:%=%-fmt)
fmttest: $(JFILES:%=%-fmttest)

%-fmt: %
	$(JSONNET_FMT) -i $(FMTFLAGS) -- $<

%-fmttest: %
	@echo "$(JSONNET_FMT) --test $(FMTFLAGS) $<"
	@if ! $(JSONNET_FMT) --test $(FMTFLAGS) -- $<; then \
	  echo "$< needs reformatting. Try: make -C manifests fmt" >&2; \
	  exit 1; \
	fi

.PHONY: all validate fmt fmttest
.PHONY: %.jsonnet-validate %-fmt %-fmttest
