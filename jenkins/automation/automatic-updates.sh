#!/usr/bin/env bash
set -o errexit
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/functions"

print_usage() {
  echo "Usage: $0 <directory>"
}

if [[ $# -ne 1 ]]; then
  print_usage
  exit 1
fi

# check if required tools and environment variables are present
validate_environment

# clone repository and change to repo_dir
repo_dir="${1}"
clone_repo "${UPSTREAM_REPO_URL}" "${repo_dir}"
cd "${repo_dir}"

# prepare list of branches to update
BRANCHES=("master")
for b in $(filter_branches "origin/${RELEASES_BRANCH_GLOB}" | sort -Vr | head -n2); do
  BRANCHES+=("${b}")
done

configure_git
add_remote "${GITHUB_USER}" "https://${GITHUB_USER}@${DEVELOPMENT_REPO_URL/https:\/\/}"

for base_branch in "${BRANCHES[@]}"; do
  git checkout -b "${base_branch}" "origin/${base_branch}" --quiet
  if [[ -f "${MANIFESTS_IMAGES_JSON}" ]]; then
    for component in $(grep -oE "${IMAGE_NAME_REGEX}" "${MANIFESTS_IMAGES_JSON}"); do
      info "[${base_branch}] Checking updates for '${component%%:*}'..."
      # loop through every published image tag until `update_component_image` returns 0
      # this loop natually switches to the relavant version series for release branches
      for tag in $(curl -sSL "https://registry.hub.docker.com/v1/repositories/${component%%:*}/tags" | jq -r '.[]|select(.name|test("[0-9]+\\.[0-9]+\\.[0-9]+-r[0-9]+"))|.name' | sort -Vr); do
        if update_component_image "${GITHUB_USER}" "${base_branch}" "${component%%:*}:${tag}"; then
          break
        fi
      done
    done
  else
    warn "[${base_branch}] '${MANIFESTS_IMAGES_JSON/${DEVELOPMENT_DIR}}' not found. Skipping!"
  fi
done
