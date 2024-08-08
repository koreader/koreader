# Use the git commit count as the (integer) Android version code
ANDROID_VERSION ?= $(shell git rev-list --count HEAD)
ANDROID_NAME ?= $(VERSION)
ANDROID_APK = koreader-android-$(ANDROID_ARCH)$(KODEDUG_SUFFIX)-$(VERSION).apk
ANDROID_DIR = $(PLATFORM_DIR)/android
ANDROID_LAUNCHER_DIR = $(ANDROID_DIR)/luajit-launcher
ANDROID_LAUNCHER_BUILD = $(INSTALL_DIR)/luajit-launcher
ANDROID_ASSETS = $(ANDROID_LAUNCHER_BUILD)/assets
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

androiddev: update
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) dev

update: all
	# Note: do not remove the module directory so there's no need
	# for `mk7z.sh` to always recreate `assets.7z` from scratch.
	rm -rfv $(ANDROID_LIBS)
	# APK version
	mkdir -p $(ANDROID_ASSETS)/module $(ANDROID_LIBS)
	# We need strip the version, or versioned
	# libraries won't be included in the APK.
	for src in $(INSTALL_DIR)/koreader/libs/*; do \
	  dst="$${src##*/}"; \
	  dst="$${dst%%.[0-9]*}"; \
	  llvm-strip --strip-unneeded "$$src" -o $(ANDROID_LIBS)/"$$dst"; \
	done
	# binaries are stored as shared libraries to prevent W^X exception on Android 10+
	# https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission
	llvm-strip --strip-unneeded $(INSTALL_DIR)/koreader/sdcv -o $(ANDROID_LIBS)/libsdcv.so
	printf '%s\n' 'libs .' 'sdcv libsdcv.so' >$(ANDROID_ASSETS)/module/map.txt
	# assets are compressed manually and stored inside the APK.
	cd $(INSTALL_DIR)/koreader && \
		./tools/mk7z.sh \
		$(abspath $(ANDROID_ASSETS)/module/koreader.7z) \
		"$$(git show -s --format='%ci')" \
		-m0=lzma2 -mx=9 \
		-- . \
		'-x!cache' \
		'-x!clipboard' \
		'-x!data/dict' \
		'-x!data/tessdata' \
		'-x!history' \
		'-x!l10n/templates' \
		'-x!libs' \
		'-x!ota' \
		'-x!resources/fonts*' \
		'-x!resources/icons/src*' \
		'-x!rocks/bin' \
		'-x!rocks/lib/luarocks' \
		'-x!screenshots' \
		'-x!sdcv' \
		'-x!spec' \
		'-x!tools' \
		'-xr!.*' \
		'-xr!COPYING' \
		'-xr!NOTES.txt' \
		'-xr!NOTICE' \
		'-xr!README.md' \
		;
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

PHONY += androiddev update
