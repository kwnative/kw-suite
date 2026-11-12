#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 N.Leiten
# SPDX-License-Identifier: GPL-3.0-only
# Synthetic Git/archive fixtures only. No real submodule, network, game or Wine mutation.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/kw-release-test.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
project="$scratch/project"
mkdir -p "$project/tools" "$project/profiles"
cp "$root/tools/release.sh" "$project/tools/"
cp "$root/Makefile" "$root/.gitignore" "$root/.gitmodules" "$project/"
printf '/private-work/\n' >> "$project/.gitignore"
cp "$root/profiles/"*.mk "$project/profiles/"
printf 'fixture source\n' > "$project/README.md"
git init -q -b main "$project"
git -C "$project" config user.name 'Packaging fixture'
git -C "$project" config user.email 'fixture@example.invalid'
for component in kw_modloader kw_plugin_ui; do
    mkdir -p "$project/$component"
    git init -q -b main "$project/$component"
    git -C "$project/$component" config user.name 'Packaging fixture'
    git -C "$project/$component" config user.email 'fixture@example.invalid'
    printf '%s source\n' "$component" > "$project/$component/source.txt"
    printf '/build/\n' > "$project/$component/.gitignore"
    git -C "$project/$component" add source.txt .gitignore
    git -C "$project/$component" commit -qm 'Fixture component'
    revision=$(git -C "$project/$component" rev-parse HEAD)
    git -C "$project" update-index --add --cacheinfo "160000,$revision,$component"
done
selected=(kw_modloader kw_plugin_ui)
run() { bash "$project/tools/release.sh" "$@"; }
reject() {
    if "$@" > "$scratch/rejection.log" 2>&1; then
        printf 'FAIL expected rejection: %s\n' "$*" >&2
        exit 1
    fi
}
reject run verify stable "${selected[@]}"
git -C "$project" add Makefile README.md .gitignore .gitmodules profiles tools
git -C "$project" commit -qm 'Fixture composition'
run verify stable "${selected[@]}"

# A fresh clone can bootstrap only selected components using relative URLs.
# Local-file transport is allowed only inside this isolated synthetic fixture.
mkdir -p "$scratch/remotes"
for component in "${selected[@]}"; do
    git clone -q --bare "$project/$component" "$scratch/remotes/$component.git"
done
git clone -q --bare "$project" "$scratch/remotes/bundle.git"
GIT_ALLOW_PROTOCOL=file git clone -q --recurse-submodules "$scratch/remotes/bundle.git" "$scratch/fresh"
if ! GIT_ALLOW_PROTOCOL=file make -s -C "$scratch/fresh" checkout BUNDLE_PLUGINS=kw_plugin_ui > "$scratch/checkout.log" 2>&1; then
    cat "$scratch/checkout.log" >&2
    exit 1
fi
bash "$scratch/fresh/tools/release.sh" verify stable "${selected[@]}"
[[ ! -e $scratch/fresh/kw_plugin_aibot ]]

# Metadata works without any loader Makefile or SDK header.
make -s -C "$project" print-components > "$scratch/stable.txt"
! grep -qx kw_plugin_aibot "$scratch/stable.txt"
reject make -s -C "$project" print-components PROFILE=development
reject make -s -C "$project" print-components PROFILE=unknown
reject make -s -C "$project" print-components BUNDLE_PLUGINS=unknown

printf 'uncommitted selected input\n' > "$project/kw_plugin_ui/untracked.txt"
reject run verify stable "${selected[@]}"
rm "$project/kw_plugin_ui/untracked.txt"
mkdir "$project/private-work"
printf 'private local plugin work\n' > "$project/private-work/private.txt"
run verify stable "${selected[@]}"
reject run verify stable "${selected[@]}" kw_plugin_aibot

printf 'uncommitted composition input\n' >> "$project/README.md"
reject run verify stable "${selected[@]}"
git -C "$project" show HEAD:README.md > "$project/README.md"
reject run verify stable ../outside
reject run package stable ../bad "$project/build/bundle" "$project/dist" "${selected[@]}"

bundle="$project/build/stable/bundle"
mkdir -p "$bundle"
printf 'fixture runtime only\n' > "$bundle/dinput8.dll"
printf '{}\n' > "$bundle/bundle-manifest.json"
export BUILD_TIMESTAMP=202611121230
reject env BUILD_TIMESTAMP=bad bash "$project/tools/release.sh" \
    package stable v0.0.0-test "$bundle" "$project/dist" "${selected[@]}"
run package stable v0.0.0-test "$bundle" "$project/dist" "${selected[@]}"
name=kw-plugins-v0.0.0-test-stable-202611121230
(cd "$project/dist" && sha256sum -c "$name-SHA256SUMS")
tar -tzf "$project/dist/$name-sources.tar.gz" > "$scratch/source-list.txt"
grep -qx "$name/kw_modloader/source.txt" "$scratch/source-list.txt"
grep -qx "$name/kw_plugin_ui/source.txt" "$scratch/source-list.txt"
! grep -q "$name/kw_plugin_aibot/source.txt" "$scratch/source-list.txt"
! grep -q "$name/private-work/" "$scratch/source-list.txt"
! grep -Eq '/\.git/|/build/' "$scratch/source-list.txt"
unzip -Z1 "$project/dist/$name-windows-x86.zip" > "$scratch/binary-list.txt"
grep -qx BUILD-INFO.txt "$scratch/binary-list.txt"
grep -qx dinput8.dll "$scratch/binary-list.txt"
grep -qx timestamp_utc=202611121230 "$project/dist/$name-build-info.txt"
reject run package stable v0.0.0-test "$bundle" "$project/dist" "${selected[@]}"

printf 'changed component revision\n' >> "$project/kw_plugin_ui/source.txt"
git -C "$project/kw_plugin_ui" add source.txt
git -C "$project/kw_plugin_ui" commit -qm 'Changed fixture component'
reject run verify stable "${selected[@]}"
printf 'PASS release profiles, fresh-clone checkout, pinned/clean sources, unselected work, archives, checksums and overwrite refusal\n'
