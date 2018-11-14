export VERSION ?= $(shell git describe --tags --dirty)
export GIT_TAG ?= $(shell git rev-parse HEAD)

GITHUB_USER ?= bitnami
GITHUB_REPO ?= kube-prod-runtime
GITHUB_TOKEN ?=

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
	echo -n > jenkins/Changes.lst ; \
	for pr in $$(git log $${PREV_VERSION}..$(GIT_TAG) --pretty=format:"%s" | grep '(#[0-9]*)$$' | cut -d"#" -f2 | cut -d' ' -f1); do \
		wget -q --header "Authorization: token $${GITHUB_TOKEN}" "https://api.github.com/repos/$(GITHUB_USER)/$(GITHUB_REPO)/pulls/$${pr}" -O - | \
			jq -r '[.number,.title,.user.login] | "- \(.[1]) (#\(.[0])) - @\(.[2])"' >> jenkins/Changes.lst ; \
	done ; \
	if [ $$(cat jenkins/Changes.lst | wc -l) -eq 0 ]; then \
		git log $${PREV_VERSION}..$(GIT_TAG) --pretty=format:"- %s" >> jenkins/Changes.lst ; \
		echo >> jenkins/Changes.lst ; \
	fi ; \
	git cat-file -p $(GIT_TAG) | sed '/-----BEGIN PGP SIGNATURE-----/,/-----END PGP SIGNATURE-----/d' | tail -n +6 > Release_Notes.md ; \
	cat jenkins/Release_Notes.md.tmpl >> Release_Notes.md ; \
	cat jenkins/Changes.lst >> Release_Notes.md ; \
	rm -f jenkins/Changes.lst

release-notes: Release_Notes.md

dist:
	$(MAKE) -C kubeprod $@

publish: github-release release-notes
ifndef GITHUB_TOKEN
	$(error You must specify the GITHUB_TOKEN)
endif
	github-release delete --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(GIT_TAG)' || :
	@set -e ; \
	PRE_RELEASE=$${VERSION##*-rc} ; cat Release_Notes.md | github-release release $${PRE_RELEASE:+--pre-release} --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(GIT_TAG)' -n 'BKPR $(VERSION)' -d -
	for f in $$(ls kubeprod/_dist/*.gz kubeprod/_dist/*.zip) ; do github-release upload --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(GIT_TAG)' --name "$$(basename $${f})" --file "$${f}" ; done

clean:
	rm -f Release_Notes.md
	$(MAKE) -C kubeprod $@

HAS_GITHUB_RELEASE := $(shell command -v github-release;)

github-release:
ifndef HAS_GITHUB_RELEASE
	$(GO) get github.com/aktau/github-release
endif
