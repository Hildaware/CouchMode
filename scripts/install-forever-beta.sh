#!/usr/bin/env bash

# Install this checkout into the WoW Forever beta client. Pass the WoW install
# directory as the first argument to use a non-default installation location.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wow_dir="${1:-/Applications/World of Warcraft}"
addon_dir="${wow_dir}/_classic_beta_/Interface/AddOns/CouchMode"

if [[ ! -d "${wow_dir}/_classic_beta_" ]]; then
    printf 'WoW Forever beta client was not found at: %s\n' "${wow_dir}/_classic_beta_" >&2
    printf 'Usage: %s [path-to-World-of-Warcraft]\n' "$0" >&2
    exit 1
fi

mkdir -p "${addon_dir}"
rsync -a --delete \
    --exclude '/.git/' \
    --exclude '/.github/' \
    --exclude '/scripts/' \
    --exclude '/.gitignore' \
    --exclude '/README.md' \
    "${repo_dir}/" "${addon_dir}/"

printf 'Installed CouchMode to %s\n' "${addon_dir}"
