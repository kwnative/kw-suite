#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 N.Leiten
# SPDX-License-Identifier: GPL-3.0-only
# Mock the GitHub CLI. These fixtures cannot contact GitHub or publish anything.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/kw-publish-test.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/bin" "$scratch/dist"
export GH_REPO=fixture/kw-suite GH_TOKEN=fixture-token
export PUBLISH_LOG="$scratch/calls" PATH="$scratch/bin:$PATH"
cat > "$scratch/bin/gh" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$PUBLISH_LOG"
if [[ ${FAIL_CREATE:-0} == 1 && $2 == create ]]; then exit 1; fi
SH
chmod +x "$scratch/bin/gh"
prepare() {
    local tag=$1 prefix="kw-plugins-$1-stable-202611121230"
    rm -f "$scratch/dist/"*
    for suffix in windows-x86.zip sources.tar.gz build-info.txt; do
        printf 'fixture %s\n' "$suffix" > "$scratch/dist/$prefix-$suffix"
    done
    (cd "$scratch/dist" && sha256sum "$prefix-windows-x86.zip" "$prefix-sources.tar.gz" "$prefix-build-info.txt" > "$prefix-SHA256SUMS")
    : > "$PUBLISH_LOG"
}
reject() {
    if "$@" > "$scratch/rejection.log" 2>&1; then echo 'FAIL expected refusal' >&2; exit 1; fi
}
prepare v0.1.0-alpha.1
bash "$root/tools/publish_release.sh" v0.1.0-alpha.1 "$scratch/dist"
grep -q -- '--prerelease --latest=false' "$PUBLISH_LOG"
grep -q -- '--verify-tag --draft --generate-notes' "$PUBLISH_LOG"
grep -qx 'release edit v0.1.0-alpha.1 --draft=false' "$PUBLISH_LOG"
prepare v0.1.0
bash "$root/tools/publish_release.sh" v0.1.0 "$scratch/dist"
! grep -q -- '--prerelease' "$PUBLISH_LOG"
prepare v0.1.0
reject env FAIL_CREATE=1 bash "$root/tools/publish_release.sh" v0.1.0 "$scratch/dist"
! grep -q 'release edit' "$PUBLISH_LOG"
prepare v0.1.0
printf 'corrupt asset\n' >> "$scratch/dist/kw-plugins-v0.1.0-stable-202611121230-windows-x86.zip"
reject bash "$root/tools/publish_release.sh" v0.1.0 "$scratch/dist"
[[ ! -s $PUBLISH_LOG ]]
printf 'PASS mock release: prerelease/stable flags, draft-before-publish, upload failure and checksum refusal\n'
