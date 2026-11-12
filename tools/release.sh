#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 N.Leiten
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
export LC_ALL=C
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
die() { printf 'Release: %s\n' "$*" >&2; exit 1; }

verify() {
    local component mode type recorded actual unused
    [[ $(git -C "$root" rev-parse --show-toplevel) == "$root" ]] || die 'expected a composition repository'
    git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1 || die 'review and commit the composition repository first'
    [[ -z $(git -C "$root" status --porcelain --untracked-files=all --ignore-submodules=dirty) ]] ||
        die 'composition files or recorded component revisions are uncommitted'
    [[ ${#components[@]} -gt 0 && ${components[0]} == kw_modloader ]] || die 'select the loader first'
    for component in "${components[@]}"; do
        [[ $component =~ ^kw_(modloader|plugin_[a-z_]+)$ ]] || die "invalid component: $component"
        read -r mode type recorded unused < <(git -C "$root" ls-tree HEAD -- "$component") ||
            die "$component has no recorded revision"
        [[ $mode == 160000 && $type == commit ]] || die "$component is not a pinned submodule"
        [[ $(git -C "$root/$component" rev-parse --show-toplevel) == "$root/$component" ]] ||
            die "$component is not initialized; run make checkout"
        actual=$(git -C "$root/$component" rev-parse HEAD)
        [[ $actual == "$recorded" ]] || die "$component differs from the recorded commit"
        [[ -z $(git -C "$root/$component" status --porcelain --untracked-files=all) ]] ||
            die "$component has uncommitted files"
        [[ -z $(git -C "$root/$component" ls-files --stage | awk '$1 == "160000"') ]] ||
            die "$component has nested submodules; source packaging needs explicit support before release"
    done
    printf 'VERIFIED profile=%s components=%s\n' "$profile" "${#components[@]}"
}

[[ $# -ge 2 ]] || die 'usage: release.sh verify PROFILE COMPONENT... | package PROFILE VERSION BUNDLE DIST COMPONENT...'
command=$1
profile=$2
shift 2
[[ $profile == stable || $profile == development ]] || die 'unknown profile'
case $command in
    verify)
        components=("$@")
        verify
        exit 0
        ;;
    package)
        [[ $# -ge 4 ]] || die 'package needs version, bundle, output and components'
        version=$1
        bundle=$2
        output=$3
        shift 3
        components=("$@")
        ;;
    *) die 'unknown command' ;;
esac

[[ $version =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 'version must contain only letters, digits, dots, underscores and hyphens'
timestamp=${BUILD_TIMESTAMP:-$(date -u +%Y%m%d%H%M)}
[[ $timestamp =~ ^[0-9]{12}$ ]] || die 'BUILD_TIMESTAMP must use UTC YYYYMMDDHHmm (12 digits)'
verify
[[ -f $bundle/bundle-manifest.json && -f $bundle/dinput8.dll ]] || die 'build the composed bundle first'
[[ -z $(find "$bundle" -type l -print -quit) ]] || die 'bundle contains a symlink'
mkdir -p -- "$output"
output=$(cd -- "$output" && pwd -P)
name="kw-plugins-$version-$profile-$timestamp"
binary="$name-windows-x86.zip"
sources="$name-sources.tar.gz"
info="$name-build-info.txt"
checksums="$name-SHA256SUMS"
lock="$output/.$name.lock"
mkdir -- "$lock" || die 'another writer holds this artifact name'
work=''
cleanup() {
    [[ -z $work ]] || rm -rf -- "$work"
    rmdir -- "$lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
for file in "$binary" "$sources" "$info" "$checksums"; do
    [[ ! -e $output/$file ]] || die "artifact already exists: $file; choose another VERSION or archive/remove the old set"
done
work=$(mktemp -d "$output/.$name.XXXXXXXX")
mkdir -p "$work/runtime" "$work/source/$name"

{
    printf 'format=kw-plugins-build-v1\nversion=%s\nprofile=%s\n' "$version" "$profile"
    printf 'timestamp_utc=%s\n' "$timestamp"
    printf 'composition=%s\n' "$(git -C "$root" rev-parse HEAD)"
    for component in "${components[@]}"; do
        printf 'component.%s=%s\n' "$component" "$(git -C "$root/$component" rev-parse HEAD)"
    done
    printf 'host=linux\ntarget=windows-x86\n'
    printf 'make=%s\n' "$(make --version | sed -n '1p')"
    printf 'windows_cc=%s\n' "$("${WINDOWS_CC:-i686-w64-mingw32-gcc}" --version | sed -n '1p')"
    printf 'windows_cxx=%s\n' "$("${WINDOWS_CXX:-i686-w64-mingw32-g++}" --version | sed -n '1p')"
    printf 'host_cxx=%s\n' "$("${HOST_CXX:-c++}" --version | sed -n '1p')"
} > "$work/$info"

cp -a -- "$bundle/." "$work/runtime/"
cp -- "$work/$info" "$work/runtime/BUILD-INFO.txt"
(cd -- "$work/runtime" && zip -q -r "$work/$binary" .)

# git archive excludes .git, ignored output, operator files and uncommitted content.
git -C "$root" archive --format=tar HEAD | tar -xf - -C "$work/source/$name"
for component in "${components[@]}"; do
    git -C "$root/$component" archive --format=tar --prefix="$component/" HEAD |
        tar -xf - -C "$work/source/$name"
done
cp -- "$work/$info" "$work/source/$name/RELEASE-BUILD-INFO.txt"
tar --sort=name -cf - -C "$work/source" "$name" | gzip -n > "$work/$sources"
(cd -- "$work" && sha256sum "$binary" "$sources" "$info" > "$checksums")
# Catch source edits or changed pins during packaging too.
verify
for file in "$binary" "$sources" "$info" "$checksums"; do
    mv -- "$work/$file" "$output/$file"
done
printf 'ARTIFACTS %s\n' "$output/$name"
