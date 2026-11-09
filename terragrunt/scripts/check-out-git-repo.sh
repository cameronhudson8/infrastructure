#!/usr/bin/env bash

# This script is intended for use with the "external" Terraform data source.
# See https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external

set -eu -o pipefail
export SHELLOPTS

QUERY=$(cat /dev/stdin)
REF=$(jq -er '.ref' <<<"${QUERY}")
REPO_URI=$(jq -er '.repoUri' <<<"${QUERY}")

repo_name=$(basename "${REPO_URI}" | sed 's/\.git//')

git_clone_dir="/tmp/repos/${repo_name}"
if ! [ -d "${git_clone_dir}" ]; then
    mkdir -p "${git_clone_dir}"
fi
(
    cd "${git_clone_dir}"

    if [ ! -d '.git' ]; then
        git init --quiet
    fi

    if ! git remote get-url origin >/dev/null 2>&1; then
        git remote add origin "${REPO_URI}"
    fi

    git fetch origin "${REF}" --quiet

    git checkout "${REF}" --quiet
    # If the ref is a branch, then be sure to pull the latest.
    if ! [[ "${REF}" =~ ^[a-f0-9]{7,40}$ ]]; then
        git pull --quiet
    fi
)
echo "{\"path\":\"${git_clone_dir}\"}"
