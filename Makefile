VERSION ?= dev-$(shell date +%FT%T%z)

GITHUB_USER ?= bitnami
GITHUB_REPO ?= kube-prod-runtime
GITHUB_TOKEN ?=

GO = go

Release_Notes.md:
ifndef GITHUB_TOKEN
	$(error You must specify the GITHUB_TOKEN)
endif
	git cat-file -p $(VERSION) | tail -n +6 > Release_Notes.md
	cat jenkins/Release_Notes.md.tmpl >> Release_Notes.md
	PREV_VERSION=$$(git describe --abbrev=0 --tags $$(git rev-list --tags --skip=1 --max-count=1)) ; \
	echo $${PREV_VERSION} ; \
	for pr in $$(git log $${PREV_VERSION}..$(VERSION) --pretty=format:"%s" | grep "Merge pull request" | cut -d"#" -f2 | cut -d' ' -f1); do \
		wget -q --header "Authorization: token $${GITHUB_TOKEN}" "https://api.github.com/repos/$(GITHUB_USER)/$(GITHUB_REPO)/pulls/$${pr}" -O - | \
			jq -r '[.number,.title,.user.login] | "- \(.[1]) (#\(.[0])) - @\(.[2])"' >> Release_Notes.md ; \
	done

release-notes: Release_Notes.md

dist:
	$(MAKE) -C kubeprod $@ VERSION=$(VERSION)

publish: github-release release-notes
ifndef GITHUB_TOKEN
	$(error You must specify the GITHUB_TOKEN)
endif
	github-release delete --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(VERSION)' || :
	cat Release_Notes.md | github-release release --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(VERSION)' -n 'BKPR $(VERSION)' -d -
	for f in $$(ls kubeprod/_dist/*.gz kubeprod/_dist/*.zip) ; do github-release upload --user $(GITHUB_USER) --repo $(GITHUB_REPO) --tag '$(VERSION)' --name "$$(basename $${f})" --file "$${f}" ; done ; \

clean:
	rm -rf Release_Notes.md
	$(MAKE) -C kubeprod $@

HAS_GITHUB_RELEASE := $(shell command -v github-release;)

github-release:
ifndef HAS_GITHUB_RELEASE
	$(GO) get github.com/aktau/github-release
endif
