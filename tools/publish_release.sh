#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 N.Leiten
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
die() { printf 'Publish: %s\n' "$*" >&2; exit 1; }
[[ $# == 2 ]] || die 'usage: publish_release.sh TAG DIST_DIRECTORY'
tag=$1
output=$2
[[ $tag =~ ^v[A-Za-z0-9._-]+$ ]] || die 'invalid version tag'
[[ -n ${GH_REPO:-} ]] || die 'set GH_REPO to the target owner/repository'
[[ -n ${GH_TOKEN:-} ]] || die 'set GH_TOKEN to the release token'
shopt -s nullglob
checksum_files=("$output"/kw-plugins-"$tag"-stable-*-SHA256SUMS)
[[ ${#checksum_files[@]} == 1 ]] || die 'expected exactly one checksum file for this tag'
prefix=${checksum_files[0]%-SHA256SUMS}
assets=("$prefix-windows-x86.zip" "$prefix-sources.tar.gz" "$prefix-build-info.txt" "${checksum_files[0]}")
for file in "${assets[@]}"; do
    [[ -f $file ]] || die "missing release asset: $file"
done
checksum_name=$(basename -- "${checksum_files[0]}")
(cd -- "$output" && sha256sum -c "$checksum_name")
extra=()
if [[ $tag == *-* ]]; then
    extra+=(--prerelease --latest=false)
fi
# Existing tags are required; existing releases/assets are never overwritten.
# Keep the release a draft until all four uploads have succeeded.
gh release create "$tag" "${assets[@]}" --verify-tag --draft --generate-notes --title "KW Suite $tag" "${extra[@]}"
gh release edit "$tag" --draft=false
