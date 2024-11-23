# Use the git commit count as the (integer) Android version code
ANDROID_VERSION ?= $(shell git rev-list --count HEAD)
ANDROID_NAME ?= $(VERSION)
ANDROID_APK = koreader-android-$(ANDROID_ARCH)$(KODEDUG_SUFFIX)-$(ANDROID_NAME).apk

# Run. {{{

PHONY += run

# Tools
APKANALYZER ?= $(ANDROID_SDK_ROOT)/cmdline-tools/latest/bin/apkanalyzer

run: update
	# get android app id
ifneq (,$(DRY_RUN))
	$(eval ANDROID_APP_ID := $$$$(ANDROID_APP_ID))
	ANDROID_APP_ID="$$($(APKANALYZER) manifest application-id $(ANDROID_APK))"
else
	$(eval ANDROID_APP_ID := $(shell $(APKANALYZER) manifest application-id $(ANDROID_APK)))
	[[ -n '$(ANDROID_APP_ID)' ]]
endif
	# clear logcat to get rid of useless cruft
	adb logcat -c
	# uninstall existing package to make sure *everything* is gone from memory
	-adb uninstall $(ANDROID_APP_ID)
	# wake up target
	-adb shell input keyevent KEYCODE_WAKEUP '&'
	# install
	adb install $(ADB_INSTALL_FLAGS) '$(ANDROID_APK)'
	# there's no adb run so we do this…
	adb shell monkey -p $(ANDROID_APP_ID) -c android.intent.category.LAUNCHER 1
	# monitor logs
	./tools/logcat.py

# }}}

# Update. {{{

PHONY += androiddev update

ANDROID_DIR = $(PLATFORM_DIR)/android
ANDROID_LAUNCHER_DIR = $(ANDROID_DIR)/luajit-launcher
ANDROID_LAUNCHER_BUILD = $(INSTALL_DIR)/luajit-launcher
ANDROID_ASSETS = $(ANDROID_LAUNCHER_BUILD)/assets
# Assets compression method:
# - LZMA/LZMA2: `-m0=lzma2 -mx=9`
# - LZMA/LZMA2 (7z >= 17.02, fast version): `-m0=flzma2 -mx=9`
# - ZSTD (7z >= 17.02, LZMA still used for archive headers): `-m0=zstd -mx=16`
# - ZSTD (7z >= 17.02): `-m0=zstd -mhc=off -mx=16`
ANDROID_ASSETS_COMPRESSION ?= -m0=lzma2 -mx=9
ANDROID_LIBS = $(ANDROID_LAUNCHER_BUILD)/libs/$(ANDROID_ABI)
ANDROID_FLAVOR ?= Rocks

ifneq (,$(CI))
  GRADLE_FLAGS ?= --console=plain --no-daemon -x lintVitalArmRocksRelease
endif
GRADLE_FLAGS += $(PARALLEL_JOBS:%=--max-workers=%)

ifeq ($(ANDROID_ARCH), arm64)
  ANDROID_ABI ?= arm64-v8a
else ifeq ($(ANDROID_ARCH), x86)
  ANDROID_ABI ?= $(ANDROID_ARCH)
else ifeq ($(ANDROID_ARCH), x86_64)
  ANDROID_ABI ?= $(ANDROID_ARCH)
else
  ANDROID_ARCH ?= arm
  ANDROID_ABI ?= armeabi-v7a
endif

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autofrontlight.koplugin
plugins/hello.koplugin
plugins/timesync.koplugin
tools
endef

define UPDATE_GLOBAL_EXCLUDES +=
README.md
COPYING
LICENSE*
*license.txt
NOTICE
endef

androiddev: update
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) dev

update: all
	# Note: do not remove the module directory so there's no need
	# for `mk7z.sh` to always recreate `assets.7z` from scratch.
	rm -rf $(ANDROID_LIBS)
	# Remove old in-tree build artifacts that could conflict.
	rm -rf $(ANDROID_LAUNCHER_DIR)/assets/{libs,module}
	# APK version
	mkdir -p $(ANDROID_ASSETS)/module $(ANDROID_LIBS)
	echo $(VERSION) >$(ANDROID_ASSETS)/module/version.txt
	# We need to strip version numbers, as gradle will ignore
	# versioned libraries and not include them in the APK.
	for src in $(INSTALL_DIR)/koreader/libs/*; do \
	  dst="$${src##*/}"; \
	  dst="$${dst%%.[0-9]*}"; \
	  llvm-strip --strip-unneeded "$$src" -o $(ANDROID_LIBS)/"$$dst"; \
	done
	# binaries are stored as shared libraries to prevent W^X exception on Android 10+
	# https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission
	llvm-strip --strip-unneeded $(INSTALL_DIR)/koreader/sdcv -o $(ANDROID_LIBS)/libsdcv.so
	# Assets are compressed manually and stored inside the APK.
	cd $(INSTALL_DIR)/koreader && \
	  ./tools/mkrelease.sh \
	  $(if $(PARALLEL_JOBS),--jobs $(PARALLEL_JOBS)) \
	  --epoch="$$(git show -s --format='%ci')" \
	  --options='$(ANDROID_ASSETS_COMPRESSION)' \
	  $(abspath $(ANDROID_ASSETS)/module/koreader.7z) \
	  . '-x!libs' '-x!sdcv' $(release_excludes)
	# Note: we filter out the `--debug=…` make flag so the old
	# crummy version provided by the NDK does not blow a gasket.
	env \
		ANDROID_ARCH='$(ANDROID_ARCH)' \
		ANDROID_ABI='$(ANDROID_ABI)' \
		ANDROID_FULL_ARCH='$(ANDROID_ABI)' \
		LUAJIT_INC='$(abspath $(STAGING_DIR)/include/luajit-2.1)' \
		LUAJIT_LIB='$(abspath $(ANDROID_LIBS)/libluajit.so)' \
		MAKEFLAGS='$(filter-out --debug=%,$(MAKEFLAGS))' \
		NDK=$(ANDROID_NDK_ROOT) \
		SDK=$(ANDROID_SDK_ROOT) \
		$(ANDROID_LAUNCHER_DIR)/gradlew \
		--project-dir='$(abspath $(ANDROID_LAUNCHER_DIR))' \
		--project-cache-dir='$(abspath $(ANDROID_LAUNCHER_BUILD)/gradle)' \
		-PassetsPath='$(abspath $(ANDROID_ASSETS))' \
		-PbuildDir='$(abspath $(ANDROID_LAUNCHER_BUILD))' \
		-PlibsPath='$(abspath $(dir $(ANDROID_LIBS)))' \
		-PndkCustomPath='$(ANDROID_NDK_ROOT)' \
		-PprojectName='KOReader' \
		-PversCode='$(ANDROID_VERSION)' \
		-PversName='$(ANDROID_NAME)' \
		$(GRADLE_FLAGS) \
		'app:assemble$(ANDROID_ARCH)$(ANDROID_FLAVOR)$(if $(KODEBUG),Debug,Release)'
	cp $(ANDROID_LAUNCHER_BUILD)/outputs/apk/$(ANDROID_ARCH)$(ANDROID_FLAVOR)/$(if $(KODEBUG),debug,release)/NativeActivity.apk $(ANDROID_APK)

# }}}

# vim: foldmethod=marker foldlevel=0
