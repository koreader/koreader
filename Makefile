PHONY = all android-ndk android-sdk base clean distclean doc fetchthirdparty re static-check
SOUND = $(INSTALL_DIR)/%

# koreader-base directory
KOR_BASE ?= base

include $(KOR_BASE)/Makefile.defs

RELEASE_DATE := $(shell git show -s --format=format:"%cd" --date=short HEAD)
# We want VERSION to carry the version of the KOReader main repo, not that of koreader-base
VERSION := $(shell git describe HEAD)
# Only append date if we're not on a whole version, like v2018.11
ifneq (,$(findstring -,$(VERSION)))
	VERSION := $(VERSION)_$(RELEASE_DATE)
endif

LINUX_ARCH?=native
ifeq ($(LINUX_ARCH), native)
	LINUX_ARCH_NAME:=$(shell uname -m)
else ifeq ($(LINUX_ARCH), arm64)
	LINUX_ARCH_NAME:=aarch64
else ifeq ($(LINUX_ARCH), arm)
	LINUX_ARCH_NAME:=armv7l
endif
LINUX_ARCH_NAME?=$(LINUX_ARCH)


MACHINE=$(TARGET_MACHINE)
ifdef KODEBUG
	MACHINE:=$(MACHINE)-debug
	KODEDUG_SUFFIX:=-debug
endif

ifdef TARGET
	DIST:=$(TARGET)
else
	DIST:=emulator
endif

INSTALL_DIR ?= koreader-$(DIST)-$(MACHINE)

# platform directories
PLATFORM_DIR=platform
COMMON_DIR=$(PLATFORM_DIR)/common
WIN32_DIR=$(PLATFORM_DIR)/win32

define CR3GUI_DATADIR_EXCLUDES
%/KoboUSBMS.tar.gz
%/NOTES.txt
%/cr3.ini
%/cr3skin-format.txt
%/desktop
%/devices
%/dict
%/manual
%/tessdata
endef
CR3GUI_DATADIR_FILES = $(filter-out $(CR3GUI_DATADIR_EXCLUDES),$(wildcard $(CR3GUI_DATADIR)/*))

define DATADIR_FILES
$(CR3GUI_DATADIR_FILES)
$(OUTPUT_DIR_DATAFILES)
$(THIRDPARTY_DIR)/kpvcrlib/cr3.css
endef

# files to link from main directory
INSTALL_FILES=reader.lua setupkoenv.lua frontend resources defaults.lua datastorage.lua \
		l10n tools README.md COPYING

OUTPUT_DIR_ARTIFACTS = $(abspath $(OUTPUT_DIR))/!(cache|cmake|data|history|staging|thirdparty)
OUTPUT_DIR_DATAFILES = $(OUTPUT_DIR)/data/*

# Release excludes. {{{

define UPDATE_PATH_EXCLUDES
cache
clipboard
data/dict
data/tessdata
ev_replay.py
help
history
l10n/templates
l10n/*/*.po
ota
resources/fonts*
resources/icons/src*
screenshots
spec
endef

# Files created after execution.
define UPDATE_PATH_EXCLUDES +=
data/cr3.ini
defaults.*.lua
history.lua
scripts
settings
settings.reader.lua*
styletweaks
version.log
endef

# Testsuite leftovers.
define UPDATE_PATH_EXCLUDES +=
dummy-test-file*
file.sdr*
i18n-test
readerbookmark.*
readerhighlight.*
testdata
this-is-not-a-valid-file*
endef

# Globally excluded.
define UPDATE_GLOBAL_EXCLUDES
*.dbg
*.dSYM
*.orig
*.swo
*.swp
*.un~
.*
endef

release_excludes = $(strip $(UPDATE_PATH_EXCLUDES:%='-x!$1%') $(UPDATE_GLOBAL_EXCLUDES:%='-xr!%'))

# }}}

define mkupdate
cd $(INSTALL_DIR) &&
'$(abspath tools/mkrelease.sh)'
--epoch="$$(git log -1 --format='%cs' "$$(git describe --tags | cut -d- -f1)")"
$(if $(PARALLEL_JOBS),--jobs $(PARALLEL_JOBS))
--manifest=$(or $2,koreader)/ota/package.index
$(foreach a,$1,'$(if $(filter --%,$a),$a,$(abspath $a))') $(or $2,koreader)
$(call release_excludes,$(or $2,koreader)/)
endef

all: base mo
	install -d $(INSTALL_DIR)/koreader
	rm -f $(INSTALL_DIR)/koreader/git-rev; echo "$(VERSION)" > $(INSTALL_DIR)/koreader/git-rev
ifdef ANDROID
	rm -f android-fdroid-version; echo -e "$(ANDROID_NAME)\n$(ANDROID_VERSION)" > koreader-android-fdroid-latest
endif
	$(SYMLINK) $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/koreader/
	bash -O extglob -c '$(SYMLINK) $(OUTPUT_DIR_ARTIFACTS) $(INSTALL_DIR)/koreader/'
ifneq (,$(EMULATE_READER))
	@echo "[*] Install front spec only for the emulator"
	$(SYMLINK) spec $(INSTALL_DIR)/koreader/spec/front
	$(SYMLINK) test $(INSTALL_DIR)/koreader/spec/front/unit/data
endif
	$(SYMLINK) $(INSTALL_FILES) $(INSTALL_DIR)/koreader/
ifdef ANDROID
	$(SYMLINK) $(ANDROID_DIR)/*.lua $(INSTALL_DIR)/koreader/
endif
	@echo "[*] Install update once marker"
	@echo "# This file indicates that update once patches have not been applied yet." > $(INSTALL_DIR)/koreader/update_once.marker
ifdef WIN32
	@echo "[*] Install runtime libraries for win32..."
	$(SYMLINK) $(WIN32_DIR)/*.dll $(INSTALL_DIR)/koreader/
endif
	@echo "[*] Install plugins"
	$(SYMLINK) plugins $(INSTALL_DIR)/koreader/
	@echo "[*] Install resources"
	$(SYMLINK) resources/fonts/* $(INSTALL_DIR)/koreader/fonts/
	install -d $(INSTALL_DIR)/koreader/{screenshots,fonts/host,ota}
	# Note: the data dir is distinct from the one in base/build/…!
	@echo "[*] Install data files"
	! test -L $(INSTALL_DIR)/koreader/data || rm $(INSTALL_DIR)/koreader/data
	install -d $(INSTALL_DIR)/koreader/data
	$(SYMLINK) $(strip $(DATADIR_FILES)) $(INSTALL_DIR)/koreader/data/

base: base-all

ifeq (,$(wildcard $(KOR_BASE)/Makefile $(KOR_BASE)/Makefile.defs))
$(KOR_BASE)/Makefile $(KOR_BASE)/Makefile.defs: fetchthirdparty
	# Need a recipe, even if empty, or make won't know how to remake `base-all`.
endif

fetchthirdparty:
	git submodule sync --recursive
ifneq (,$(CI))
	git submodule update --depth 1 --jobs 3 --init --recursive
else
	# Force shallow clones of submodules configured as such.
	git submodule update --jobs 3 --depth 1 --init $(shell \
		git config --file=.gitmodules --name-only --get-regexp '^submodule\.[^.]+\.shallow$$' true \
		| sed 's/\.shallow$$/.path/' \
		| xargs -n1 git config --file=.gitmodules \
		)
	# Update the rest.
	git submodule update --jobs 3 --init --recursive
endif

clean: base-clean mo-clean
	rm -rf $(INSTALL_DIR)

distclean: clean base-distclean
	$(MAKE) -C doc clean

re: clean
	$(MAKE) all

# Include emulator specific rules.
ifneq (,$(EMULATE_READER))
  include make/emulator.mk
endif

# Include target specific rules.
ifneq (,$(wildcard make/$(TARGET).mk))
  include make/$(TARGET).mk
endif

include make/gettext.mk

android-ndk:
	$(MAKE) -C $(KOR_BASE)/toolchain $(ANDROID_NDK_HOME)

android-sdk:
	$(MAKE) -C $(KOR_BASE)/toolchain $(ANDROID_HOME)

static-check:
	@if which luacheck > /dev/null; then \
			luacheck -q {reader,setupkoenv,datastorage}.lua frontend plugins spec; \
		else \
			echo "[!] luacheck not found. "\
			"you can install it with 'luarocks install luacheck'"; \
		fi

doc:
	make -C doc

.NOTPARALLEL:
.PHONY: $(PHONY)

include $(KOR_BASE)/Makefile

# vim: foldmethod=marker foldlevel=0
