# koreader-base directory
KOR_BASE?=base

include $(KOR_BASE)/Makefile.defs

# We want VERSION to carry the version of the KOReader main repo, not that of koreader-base
VERSION:=$(shell git describe HEAD)
# Only append date if we're not on a whole version, like v2018.11
ifneq (,$(findstring -,$(VERSION)))
	VERSION:=$(VERSION)_$(shell git show -s --format=format:"%cd" --date=short HEAD)
endif

# releases do not contain tests and misc data
IS_RELEASE := $(if $(or $(EMULATE_READER),$(WIN32)),,1)
IS_RELEASE := $(if $(or $(IS_RELEASE),$(APPIMAGE),$(LINUX),$(MACOS)),1,)

ifeq ($(ANDROID_ARCH), arm64)
	ANDROID_ABI?=arm64-v8a
else ifeq ($(ANDROID_ARCH), x86)
	ANDROID_ABI?=$(ANDROID_ARCH)
else ifeq ($(ANDROID_ARCH), x86_64)
	ANDROID_ABI?=$(ANDROID_ARCH)
else
	ANDROID_ARCH?=arm
	ANDROID_ABI?=armeabi-v7a
endif

# Use the git commit count as the (integer) Android version code
ANDROID_VERSION?=$(shell git rev-list --count HEAD)
ANDROID_NAME?=$(VERSION)

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

# files to link from main directory
INSTALL_FILES=reader.lua setupkoenv.lua frontend resources defaults.lua datastorage.lua \
		l10n tools README.md COPYING

ifeq ($(abspath $(OUTPUT_DIR)),$(OUTPUT_DIR))
  ABSOLUTE_OUTPUT_DIR = $(OUTPUT_DIR)
else
  ABSOLUTE_OUTPUT_DIR = $(KOR_BASE)/$(OUTPUT_DIR)
endif
OUTPUT_DIR_ARTIFACTS = $(ABSOLUTE_OUTPUT_DIR)/!(cache|history|thirdparty)

all: base
	install -d $(INSTALL_DIR)/koreader
	rm -f $(INSTALL_DIR)/koreader/git-rev; echo "$(VERSION)" > $(INSTALL_DIR)/koreader/git-rev
ifdef ANDROID
	rm -f android-fdroid-version; echo -e "$(ANDROID_NAME)\n$(ANDROID_VERSION)" > koreader-android-fdroid-latest
endif
ifeq ($(IS_RELEASE),1)
	bash -O extglob -c '$(RCP) -fL $(OUTPUT_DIR_ARTIFACTS) $(INSTALL_DIR)/koreader/'
else
	cp -f $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/koreader/
	@echo "[*] create symlink instead of copying files in development mode"
	bash -O extglob -c '$(SYMLINK) $(OUTPUT_DIR_ARTIFACTS) $(INSTALL_DIR)/koreader/'
  ifneq (,$(EMULATE_READER))
	@echo "[*] install front spec only for the emulator"
	$(SYMLINK) $(abspath spec) $(INSTALL_DIR)/koreader/spec/front
	$(SYMLINK) $(abspath test) $(INSTALL_DIR)/koreader/spec/front/unit/data
  endif
endif
	$(SYMLINK) $(abspath $(INSTALL_FILES)) $(INSTALL_DIR)/koreader/
ifdef ANDROID
	$(SYMLINK) $(abspath $(ANDROID_DIR)/*.lua) $(INSTALL_DIR)/koreader/
endif
	@echo "[*] Install update once marker"
	@echo "# This file indicates that update once patches have not been applied yet." > $(INSTALL_DIR)/koreader/update_once.marker
ifdef WIN32
	@echo "[*] Install runtime libraries for win32..."
	$(SYMLINK) $(abspath $(WIN32_DIR)/*.dll) $(INSTALL_DIR)/koreader/
endif
ifdef SHIP_SHARED_STL
	@echo "[*] Install C++ runtime..."
	cp -fL $(SHARED_STL_LIB) $(INSTALL_DIR)/koreader/libs/
	chmod 755 $(INSTALL_DIR)/koreader/libs/$(notdir $(SHARED_STL_LIB))
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/koreader/libs/$(notdir $(SHARED_STL_LIB))
endif
	@echo "[*] Install plugins"
	$(SYMLINK) $(abspath plugins) $(INSTALL_DIR)/koreader/
	@echo "[*] Install resources"
	$(SYMLINK) $(abspath resources/fonts/*) $(INSTALL_DIR)/koreader/fonts/
	install -d $(INSTALL_DIR)/koreader/{screenshots,data/{dict,tessdata},fonts/host,ota}
ifeq ($(IS_RELEASE),1)
	@echo "[*] Clean up, remove unused files for releases"
	rm -rf $(INSTALL_DIR)/koreader/data/{cr3.ini,cr3skin-format.txt,desktop,devices,manual}
endif

base:
	$(MAKE) -C $(KOR_BASE)

$(INSTALL_DIR)/koreader/.busted: .busted
	$(SYMLINK) $(abspath .busted) $@

$(INSTALL_DIR)/koreader/.luacov:
	$(SYMLINK) $(abspath .luacov) $@

testfront: $(INSTALL_DIR)/koreader/.busted
	# sdr files may have unexpected impact on unit testing
	-rm -rf spec/unit/data/*.sdr
	cd $(INSTALL_DIR)/koreader && $(BUSTED_LUAJIT) $(BUSTED_OVERRIDES) $(BUSTED_SPEC_FILE)

test: $(INSTALL_DIR)/koreader/.busted
	$(MAKE) -C $(KOR_BASE) test
	$(MAKE) testfront

coverage: $(INSTALL_DIR)/koreader/.luacov
	-rm -rf $(INSTALL_DIR)/koreader/luacov.*.out
	cd $(INSTALL_DIR)/koreader && \
		./luajit $(shell which busted) --output=gtest \
			--sort-files \
			--coverage --exclude-tags=nocov
	# coverage report summary
	cd $(INSTALL_DIR)/koreader && tail -n \
		+$$(($$(grep -nm1 -e "^Summary$$" luacov.report.out|cut -d: -f1)-1)) \
		luacov.report.out

$(KOR_BASE)/Makefile.defs fetchthirdparty:
	git submodule init
	git submodule sync
ifneq (,$(CI))
	git submodule update --depth 1 --jobs 3
else
	# Force shallow clones of submodules configured as such.
	git submodule update --jobs 3 --depth 1 $(shell \
		git config --file=.gitmodules --name-only --get-regexp '^submodule\.[^.]+\.shallow$$' true \
		| sed 's/\.shallow$$/.path/' \
		| xargs -n1 git config --file=.gitmodules \
		)
	# Update the rest.
	git submodule update --jobs 3
endif
	$(MAKE) -C $(KOR_BASE) fetchthirdparty

VERBOSE ?= @
Q = $(VERBOSE:1=)
clean:
	rm -rf $(INSTALL_DIR)
	$(Q:@=@echo 'MAKE -C base clean'; &> /dev/null) \
		$(MAKE) -C $(KOR_BASE) clean
ifeq ($(TARGET), android)
	$(MAKE) -C $(CURDIR)/platform/android/luajit-launcher clean
endif

dist-clean: clean
	rm -rf $(INSTALL_DIR)
	$(MAKE) -C $(KOR_BASE) dist-clean
	$(MAKE) -C doc clean

# Include target specific rules.
ifneq (,$(wildcard make/$(TARGET).mk))
  include make/$(TARGET).mk
endif

android-ndk:
	$(MAKE) -C $(KOR_BASE)/toolchain $(ANDROID_NDK_HOME)

android-sdk:
	$(MAKE) -C $(KOR_BASE)/toolchain $(ANDROID_HOME)

# for gettext
DOMAIN=koreader
TEMPLATE_DIR=l10n/templates
XGETTEXT_BIN=xgettext

pot: po
	mkdir -p $(TEMPLATE_DIR)
	$(XGETTEXT_BIN) --from-code=utf-8 \
		--keyword=C_:1c,2 --keyword=N_:1,2 --keyword=NC_:1c,2,3 \
		--add-comments=@translators \
		reader.lua `find frontend -iname "*.lua" | sort` \
		`find plugins -iname "*.lua" | sort` \
		`find tools -iname "*.lua" | sort` \
		-o $(TEMPLATE_DIR)/$(DOMAIN).pot

po:
	git submodule update --remote l10n


static-check:
	@if which luacheck > /dev/null; then \
			luacheck -q {reader,setupkoenv,datastorage}.lua frontend plugins spec; \
		else \
			echo "[!] luacheck not found. "\
			"you can install it with 'luarocks install luacheck'"; \
		fi

doc:
	make -C doc

.PHONY: all android-ndk android-sdk base clean doc test
