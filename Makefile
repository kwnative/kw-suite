# SPDX-FileCopyrightText: 2026 N.Leiten
# SPDX-License-Identifier: GPL-3.0-only
# Composition only: component repositories own their implementations and builds.
REPOS_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PROFILE ?= stable
PROFILE_FILE := $(REPOS_ROOT)/profiles/$(PROFILE).mk
ifneq ($(PROFILE),stable)
$(error PROFILE must be stable; unreleased components are not part of this suite)
endif
include $(PROFILE_FILE)
PLUGINS := kw_plugin_ui kw_plugin_gameplay kw_plugin_pacing kw_plugin_fps_patch
ifneq ($(filter-out $(PLUGINS),$(BUNDLE_PLUGINS)),)
$(error Unknown BUNDLE_PLUGINS entry: $(filter-out $(PLUGINS),$(BUNDLE_PLUGINS)))
endif
COMPONENTS := kw_modloader $(BUNDLE_PLUGINS)
KWMOD_SDK_ROOT ?= $(REPOS_ROOT)/kw_modloader
# Metadata/checkout targets must work before the loader submodule is populated.
ifneq ($(wildcard $(KWMOD_SDK_ROOT)/mk/stage_tool.mk),)
include $(KWMOD_SDK_ROOT)/mk/stage_tool.mk
endif
BUNDLE_DIR ?= $(REPOS_ROOT)/build/$(PROFILE)/bundle
DIST_DIR ?= $(REPOS_ROOT)/dist
VERSION ?= dev-$(shell git -C "$(REPOS_ROOT)" rev-parse --short=12 HEAD 2>/dev/null || printf uncommitted)
BUILD_TIMESTAMP ?= $(shell date -u +%Y%m%d%H%M)
.PHONY: all loader $(PLUGINS) example bundle stage checkout print-components verify artifacts test
.DEFAULT_GOAL := all
all: loader $(BUNDLE_PLUGINS)
loader:
	$(MAKE) -C "$(KWMOD_SDK_ROOT)" all
$(PLUGINS): loader
	$(MAKE) -C "$(REPOS_ROOT)/$@" KWMOD_SDK_ROOT="$(KWMOD_SDK_ROOT)" all
example: loader
	$(MAKE) -C "$(KWMOD_SDK_ROOT)" example
print-components:
	@printf '%s\n' $(COMPONENTS)
checkout:
	git -C "$(REPOS_ROOT)" submodule update --init --checkout --recursive -- $(COMPONENTS)
verify:
	@test "$(abspath $(KWMOD_SDK_ROOT))" = "$(REPOS_ROOT)/kw_modloader" || \
	    { echo 'Release artifacts require the pinned SDK checkout.' >&2; exit 2; }
	@test -z "$(KWMOD_BIN_DIR)" -o "$(abspath $(KWMOD_BIN_DIR))" = "$(REPOS_ROOT)/kw_modloader/build/bin" || \
	    { echo 'Use the pinned SDK build/bin for release artifacts.' >&2; exit 2; }
	@test -z "$(KWMOD_LIB_DIR)" -o "$(abspath $(KWMOD_LIB_DIR))" = "$(REPOS_ROOT)/kw_modloader/build/lib" || \
	    { echo 'Use the pinned SDK build/lib for release artifacts.' >&2; exit 2; }
	bash "$(REPOS_ROOT)/tools/release.sh" verify "$(PROFILE)" $(COMPONENTS)
# Sequential staging avoids overlapping SDK writes in recursive plugin builds.
# A single final inventory owns the composed output, not its source overlays.
bundle:
	$(MAKE) -C "$(KWMOD_SDK_ROOT)" BUNDLE_DIR="$(KWMOD_SDK_ROOT)/build/bundle" bundle
	@set -e; \
	for plugin in $(BUNDLE_PLUGINS); do \
	    $(MAKE) -C "$(REPOS_ROOT)/$$plugin" \
	        KWMOD_SDK_ROOT="$(KWMOD_SDK_ROOT)" \
	        KWMOD_BUNDLE_PROVIDERS="$(BUNDLE_PLUGINS)" \
	        BUNDLE_DIR="$(REPOS_ROOT)/$$plugin/build/bundle" bundle; \
	done
	"$(KWMOD_STAGE_TOOL)" --output "$(BUNDLE_DIR)" --component kw-composition \
	    --overlay "$(KWMOD_SDK_ROOT)/build/bundle" \
	    $(foreach plugin,$(BUNDLE_PLUGINS),--overlay "$(REPOS_ROOT)/$(plugin)/build/bundle")
stage: bundle
# Verification precedes building, and repeats before packaging to catch edits during a build.
artifacts: verify
	$(MAKE) -C "$(REPOS_ROOT)" bundle
	BUILD_TIMESTAMP="$(BUILD_TIMESTAMP)" bash "$(REPOS_ROOT)/tools/release.sh" \
	    package "$(PROFILE)" "$(VERSION)" "$(BUNDLE_DIR)" "$(DIST_DIR)" $(COMPONENTS)
test:
	bash "$(REPOS_ROOT)/tools/test_release.sh"
