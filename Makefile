VERSION ?= $(shell git rev-parse --short HEAD)

GITHUB_USER ?= bitnami
GITHUB_REPO ?= kube-prod-runtime
GITHUB_TOKEN ?=
export GITHUB_TOKEN

AWS_S3_BUCKET ?= jenkins-bkpr-releases
AWS_ACCESS_KEY_ID ?=
AWS_SECRET_ACCESS_KEY ?=
AWS_DEFAULT_REGION ?= us-east-1
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

SHELL := /bin/bash
GO = go
HAS_JQ := $(shell command -v jq;)

Release_Notes.md:
ifndef GITHUB_TOKEN
	$(warning GITHUB_TOKEN not specified, you may exceed the GitHub API rate limit. Authenticated requests get a higher rate limit.)
endif
ifndef HAS_JQ
	$(error You must install jq)
endif
	@set -e ; \
	PREV_VERSION=$$(git -c 'versionsort.suffix=-' tag --list  --sort=-v:refname | grep -m2 "^v[0-9]*\.[0-9]*\.[0-9]*$$" | tail -n1) ; \
	git log $${PREV_VERSION}..$(VERSION) --oneline | grep -v 'Merge' > jenkins/Changes.lst
	git cat-file -p $(VERSION) | sed '/-----BEGIN PGP SIGNATURE-----/,/-----END PGP SIGNATURE-----/d' | tail -n +6 > Release_Notes.md ; \
	cat jenkins/Release_Notes.md.tmpl >> Release_Notes.md ; \
	cat jenkins/Changes.lst >> Release_Notes.md ; \
	rm -f jenkins/Changes.lst

release-notes: Release_Notes.md

dist:
	$(MAKE) -C kubeprod $@

publish-to-github: github-release release-notes
ifndef GITHUB_TOKEN
	$(error You must specify the GITHUB_TOKEN)
endif
	github-release delete --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(VERSION)' || :
	@set -e ; \
	PRE_RELEASE=$${VERSION/$${VERSION%-rc[0-9]*}/} ; cat Release_Notes.md | github-release release $${PRE_RELEASE:+--pre-release} --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(VERSION)' -n 'BKPR $(VERSION)' -d - ; \
	for f in $$(ls kubeprod/_dist/*.gz kubeprod/_dist/*.zip) ; do github-release upload --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(VERSION)' --name "$$(basename $${f})" --file "$${f}" ; done

publish-to-s3: awless
ifndef AWS_ACCESS_KEY_ID
	$(error You must specify the AWS_ACCESS_KEY_ID)
endif
ifndef AWS_SECRET_ACCESS_KEY
	$(error You must specify the AWS_SECRET_ACCESS_KEY)
endif
	@set -e ; \
	awless config set autosync false --no-sync ; \
	for f in $$(find kubeprod/_dist/manifests -type f); do awless create s3object bucket=$(AWS_S3_BUCKET) file=$${f} name=files/$(VERSION)/$${f#kubeprod/_dist/} -f ; done

publish: publish-to-github publish-to-s3

clean:
	rm -f Release_Notes.md
	$(MAKE) -C kubeprod $@

HAS_GITHUB_RELEASE := $(shell command -v github-release;)
github-release:
ifndef HAS_GITHUB_RELEASE
	$(GO) get github.com/aktau/github-release
endif

HAS_AWLESS := $(shell command -v awless;)
awless:
ifndef HAS_AWLESS
	$(GO) get github.com/wallix/awless
endif
