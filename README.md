# KW Suite

[KW Suite](https://github.com/kwnative/kw-suite) builds and packages the modloader and selected independent
plugins. Component sources remain in their own repositories, recorded here as
Git submodules at exact commits. The loader SDK is the common build dependency;
each plugin owns its implementation, settings and optional cooperation contracts.

## Repository layout

```text
Makefile                    # Build and composition targets
.gitmodules                 # Component URLs; Git records their pinned commits
profiles/                   # Published plugin selections
tools/                      # Source verification, archives and packaging fixtures
.github/workflows/          # Linux builds and GitHub Actions artifact upload
kw_modloader/               # Submodule: loader, runtime and engine SDK
kw_plugin_*/                # Submodules: independent plugins
build/<profile>/bundle/     # Ignored composed runtime layout
dist/                       # Ignored binary/source archives and checksums
```

| Component | Purpose |
| --- | --- |
| [kw_modloader](https://github.com/kwnative/kw_modloader) | DirectInput entry point, lifecycle, patch ownership and shared engine SDK. |
| [kw_plugin_ui](https://github.com/kwnative/kw_plugin_ui) | Chat readability, menus, scaling and graphics presentation. |
| [kw_plugin_gameplay](https://github.com/kwnative/kw_plugin_gameplay) | Native input and Attack-Move preservation. |
| [kw_plugin_pacing](https://github.com/kwnative/kw_plugin_pacing) | Native wait and timer-resolution policy. |
| [kw_plugin_fps_patch](https://github.com/kwnative/kw_plugin_fps_patch) | Rendering framerate, interpolation and adaptive scheduling. |

Unreleased local plugins are not submodules or release components. Their ignored
working directories may remain alongside the published components for development.

## Linux prerequisites

Install Git, Bash, GNU Make 4.3+, native GCC/G++ with C++17, MinGW-w64 for
Windows i686, GNU tar, gzip, zip/unzip and coreutils. On Debian/Ubuntu:

```sh
sudo apt-get install build-essential git mingw-w64 zip unzip
```

The Windows compiler commands default to `i686-w64-mingw32-gcc`,
`i686-w64-mingw32-g++` and `i686-w64-mingw32-ar`. Native bundle staging uses
`HOST_CXX` (default `c++`). Runtime compiler libraries are linked statically;
Windows system DLLs remain required. No game installation or Wine is needed
for building. Wine is only needed for runtime testing.

Native Windows build-host support is future work. The current orchestration uses
Bash/GNU tooling and produces Windows x86 runtime files from Linux.

## Checkout and build

All component repositories are public under
[kwnative](https://github.com/kwnative). Choose either clone command below;
`--recurse-submodules` downloads the pinned modloader and plugin sources too.

### Anonymous HTTPS access

No GitHub account or SSH key is needed:

```sh
git clone --recurse-submodules https://github.com/kwnative/kw-suite.git
cd kw-suite
```

### SSH access

Use this with a GitHub account and an SSH key configured for GitHub:

```sh
git clone --recurse-submodules git@github.com:kwnative/kw-suite.git
cd kw-suite
```

Relative URLs in `.gitmodules` use the same transport as the suite checkout:
HTTPS for the first command, SSH for the second. Both clone all registered
components; the selected build profile determines which enter the bundle.

### Build or initialize an existing checkout

After either recursive clone, build the default stable bundle:

```sh
make -j2 bundle
```

If the suite was cloned without `--recurse-submodules`, initialize only the
selected profile before building:

```sh
make checkout
make -j2 bundle
```

To initialize or update all registered components in an existing checkout:

```sh
git submodule update --init --recursive
```

`make checkout` uses the recorded commits; it never follows a moving branch.
It is explicit and can contact the network. Build targets do not fetch or reset
component repositories. For active development, preserve your work before
checking out another bundle revision or running submodule update.

| Profile | Selection |
| --- | --- |
| `stable` (default) | Loader, UI, gameplay, pacing and FPS. |

```sh
make print-components PROFILE=stable
# Local custom selection; optional cooperation follows this selection:
make -j2 bundle BUNDLE_PLUGINS='kw_plugin_ui kw_plugin_pacing kw_plugin_fps_patch'
```

FPS/pacing cooperation is compiled automatically when both are selected. No
threading provider is selected. Shared SDK builds/staging are sequenced to avoid
concurrent writes; individual component compilers use the chosen Make job count.
`make` builds only the selected profile, and `make bundle` assembles its layout.
A component can still be built independently:

```sh
make -C kw_plugin_ui -j2 KWMOD_SDK_ROOT="$PWD/kw_modloader"
```

`BUNDLE_DIR` overrides the generated staging directory, `DIST_DIR` selects
archive output, and `WINDOWS_CC`, `WINDOWS_CXX`, `WINDOWS_AR`, `HOST_CXX` select
compilers. `make bundle` supports relocated SDK checkouts through
`KWMOD_SDK_ROOT`; release artifacts require the pinned SDK checkout in this
repository. See component READMEs for their detailed settings and prerequisites.

## Prepare release artifacts

From a committed composition with clean selected components:

```sh
make verify
make -j2 artifacts VERSION=v0.1.0 PROFILE=stable
```

This verifies the recorded sources, builds the selected profile and writes:

```text
dist/
  kw-plugins-v0.1.0-stable-202611121230-windows-x86.zip
  kw-plugins-v0.1.0-stable-202611121230-sources.tar.gz
  kw-plugins-v0.1.0-stable-202611121230-build-info.txt
  kw-plugins-v0.1.0-stable-202611121230-SHA256SUMS
```

The ZIP contains the ready-to-copy runtime layout, component notices and build
information. The source archive contains the composition and complete tracked
sources of the selected components, including their notices/build scripts.
It can build the selected bundle without fetching submodules; its Git-based
release targets require an actual Git checkout. Unselected component sources,
Git databases, ignored builds and operator files are excluded. Nested component
submodules are rejected until their source packaging is explicitly supported.

Build information records the composition commit, selected component commits,
profile, target, compiler versions and UTC timestamp. Every filename includes
`YYYYMMDDHHmm` (year, month, day, hour, minute in UTC). Local builds generate it
at packaging time; Actions sets it once before building so the outer artifact
name and all contained files agree. For controlled rebuilds, explicitly set
`BUILD_TIMESTAMP=202611121230` as a Make argument or environment variable.
Pinning sources does not promise bitwise
identical output across different compiler versions. Treat modified compiler
flags/toolchains as a new build configuration requiring qualification.

Packaging refuses uncommitted composition changes, changed component pins,
dirty selected components and existing output filenames. Ignored private
development directories are excluded from packaging. Archive/remove an old
artifact set or choose another version before rebuilding the same names.
Use the pinned SDK's normal `build/bin` and `build/lib` for release artifacts.

Checksums can be verified from `dist/`:

```sh
sha256sum -c kw-plugins-v0.1.0-stable-202611121230-SHA256SUMS
```

## GitHub Actions

Run manual builds and download their artifacts from
[Build bundles and releases](https://github.com/kwnative/kw-suite/actions/workflows/artifacts.yml).

The workflow builds automatically only when a **new `v*` tag** is pushed.
Ordinary branch pushes, pull requests, moved tags and deleted tags do not build.
Manual runs build the same published `stable` selection. The job checks packaging fixtures,
initializes only the chosen submodules, builds with two jobs, then uploads the
four files from `dist/` as one Actions artifact set retained for 30 days.

Tag builds use the tag as the version. Manual branch builds use `ci-<commit>`.
After a successful new-tag build, the workflow also creates a
[GitHub Release](https://github.com/kwnative/kw-suite/releases) and attaches all
four files. Tags containing a hyphen, such as `v0.1.0-alpha.1`, are marked as
prereleases and not latest. Other version tags produce normal releases.
The build job requests `contents: write` for release creation and asset upload.
The release stays a draft until all files have uploaded successfully. Existing
releases and assets are not overwritten. A failed upload may leave a draft for
inspection/removal before retrying.

Manual runs produce Actions artifacts only, even when run against a tag.
Actions artifact retention is not a permanent release archive; the tag-triggered
Release retains the binary and matching sources together.
The default checkout assumes public component repositories; private components
need separately configured read access to those repositories.

The job runs directly on the `ubuntu-24.04` hosted VM, without a job container.
GitHub's lighter `ubuntu-slim` runner has one CPU and a 15-minute job limit, which
is a poor fit for this C++/MinGW build. Adding a Debian/Alpine job container would
still need the host VM plus container setup. Keep the standard runner until
actual workflow timings justify a toolchain image or another runner setup.
See [GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

## Updating components

1. Commit, test and publish the change in its component repository under `kwnative`.
2. In this repository, select that exact component commit.
3. Stage the changed gitlink, run the bundle checks and commit the new composition.
4. Build/test the complete selection, tag the composition and upload its artifacts.

For example, after selecting a reviewed UI commit:

```sh
git add kw_plugin_ui
git commit -m 'Update UI component'
make verify
make -j2 artifacts VERSION=v0.1.1
```

Keep component histories independent. A release tag identifies one tested
combination; it does not update itself when a component branch advances.
Never use `git submodule update --remote` as part of release builds.

## Tag and publish a release

Commit and push the tested composition, then push an annotated version tag:

```sh
git push origin main
git tag -a v0.1.0-alpha.1 -m 'KW Suite v0.1.0-alpha.1'
git push origin v0.1.0-alpha.1
```

The workflow must be present in that tagged commit. Watch the Actions run; the
prerelease appears after the build, checksum verification and uploads succeed.
Use a new version tag for the next release instead of moving an existing tag.

## Manual installation

Close the game. Extract the runtime ZIP into the directory containing
`cnc3ep1.dat`, normally `<game>/RetailExe/1.2`, preserving `plugins/`, `docs/`
and `licenses/`. Keep `dinput8.dll`, `kw_runtime.dll` and `kw_engine.dll` together;
the loader is required to load the plugin manifests. Preserve customized INIs
on upgrades and merge any new settings from the supplied templates.

On Wine, use native-first `dinput8` loading if it is not already configured.
Only the modloader supplies this DirectInput proxy; other proxies need explicit
integration. There is no live `make install` target. `BUNDLE_DIR` must never point
to an installed game. No target launches a game or copies game/mod assets.

## Checks and licensing

`make test` runs synthetic Git/source/archive fixtures, not a game or network
session. Compile/package success does not replace live compatibility testing.

Composition scripts and documentation are **GPL-3.0-only**, copyright 2026
N.Leiten. See [LICENSE](LICENSE). Component code retains its own license and
permissions: the loader SDK is MIT; loader/plugin implementations and upstream
code carry their documented terms. Bundle inventories do not replace matching
source distribution obligations; consult each component's licensing notices.
