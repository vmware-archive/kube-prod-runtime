# BKPR Release Process

## Introduction

The intended audience for this document are the Bitnami Kubernetes Production Runtime (BKPR) project maintainers and it describes the workflow used to release a new major, minor or patch version of BKPR.

## The release process

BKPR consists of a collection of Kubernetes manifests written in *jsonnet* plus the accompanying `kubeprod` binary which deals with all the platform-specific details, evaluates the *jsonnet* manifests, and applies them to the existing Kubernetes cluster.

The following sections describe in detail the workfow a release manager should follow in order to prepare a new release of the BKPR project.

All BKPR releases are preceded by release candidates intended to stabilize the final release. Generally there is no set time frame within which a final release is required to be made.

BKPR releases are of the form vX.Y.Z as described in the [versioning document](versioning.md), where X is the major version number, Y is the minor version number and Z is the patch release number.

For convenience, this document assumes that the Git remote is named `origin`. Please make sure you update the listed snippets for your environment if this is not the case. If you are not sure what your upstream remote is named, use the command `git remote -v` to find out.

We are going to refer to a few environment variables which you may want to set for convenience.

For major/minor releases, use the following:

```bash
export RELEASE_NAME=vX.Y.0
export RELEASE_BRANCH_NAME="release-X.Y"
export RELEASE_CANDIDATE_NAME="$RELEASE_NAME-rc1"
```

For patch releases:

```bash
export PREVIOUS_PATCH_RELEASE=vX.Y.Z
export RELEASE_NAME=vX.Y.Z+1
export RELEASE_BRANCH_NAME="release-X.Y"
export RELEASE_CANDIDATE_NAME="$RELEASE_NAME-rc1"
```

With the environment configuration in place, follow the procedure described in the following sections.

## Step 1: Create the release branch

### Major/minor releases

As described in the [versioning document](versioning.md), major releases are for changes that break backwards compatibility and minor releases are for changes that do not break backwards compatibility.

To create a major or minor release, begin by creating a release branch from the `master` branch named `release-vX.Y.Z`.

```bash
git fetch origin
git checkout origin/master
git checkout -b $RELEASE_BRANCH_NAME
```

This new branch will be the base for our release. We will iterate over this branch to produce new release candidates and eventually stabilize the release.

### Patch releases

For major or minor releases, the release branch is created from the `master` branch. However, for patch releases, we create the release branch from the most recent patch release tag.

```bash
git fetch origin --tags
git checkout $PREVIOUS_PATCH_RELEASE
git checkout -b $RELEASE_BRANCH_NAME
```

From here, we can cherry-pick the commits we want to bring into the patch release.

This new branch will be the base for our release. We will iterate over this branch to produce new release candidates and eventually stabilize the release.

## Step 2: Commit and push the release branch

To allow contributors to test the changes in the upcoming release, we can now push the release branch upstream.

```bash
git push origin $RELEASE_BRANCH_NAME
```

Check the [build status](https://jenkins-bkpr.nami.run/blue/organizations/jenkins/kube-prod-runtime/branches) of the release branch and make sure the CI jobs have passed successfully before proceeding.

Invite other [maintainers](../MAINTAINERS) to review the changes in the branch to ensure that all required changes are committed.

## Step 3: Create a release candidate

With all the required changes in the release branch, it's time to start iterating on release candidates.

```bash
git tag --sign --annotate ${RELEASE_CANDIDATE_NAME}
git push origin ${RELEASE_CANDIDATE_NAME}
```

The CI infrastructure will automatically create a tagged Github release and the release candidate will be made available on the [releases](https://github.com/bitnami/kube-prod-runtime/releases) page.

## Step 4: Iterate on successive release candidates

The next several days should be invested in testing and stabilizing the release candidate. This time should be spent testing and finding ways in which the release might have caused various features or upgrade environments to have issues.

During this phase, the `$RELEASE_BRANCH_NAME` branch will keep evolving as you will produce new release candidates. Each time you want to produce a new release candidate, you will start by adding commits to the branch by cherry-picking from `master`:

```bash
git cherry-pick --gpg-sign -x <commit_id>
```

After that, tag and push the new release candidate:

```bash
export RELEASE_CANDIDATE_NAME="$RELEASE_NAME-rc2"
git tag --sign --annotate ${RELEASE_CANDIDATE_NAME}
git push origin $RELEASE_CANDIDATE_NAME
```

From here on just repeat this process, continuously testing until you're happy with the release candidate.

## Step 5: Write release notes

The Jenkins CI infrastructure auto-generates the changelog based on the pull requests that have been merged during the release cycle and appends the changelog of the [release notes template](../jenkins/Release_Notes.md.tmpl), but it is usually more beneficial to the end-user if the release highlights are hand-written.

For major/minor releases, listing notable user-facing features is usually sufficient. For patch releases, do the same, but make note of the symptoms and who is affected.

These release highlights should be entered while creating the tag as mentioned in the next section and the CI will automatically prepend its contents to the Release notes.

## Step 6: Finalize the release

When you are happy with the quality of a release candidate, you can create the final release tag and push the release out for general availability.

```bash
git checkout $RELEASE_BRANCH_NAME
git tag --sign --annotate ${RELEASE_NAME}
git push origin $RELEASE_NAME
```

After the release has passed the tests successfully, the CI pipeline will automatically package the BKPR release binary and the BKPR jsonnet manifests for the release. The package will then be made available to download from the project [releases](https://github.com/bitnami/kube-prod-runtime/releases) page.
