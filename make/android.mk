ANDROID_DIR = $(PLATFORM_DIR)/android
ANDROID_LAUNCHER_DIR = $(ANDROID_DIR)/luajit-launcher
ANDROID_ASSETS = $(ANDROID_LAUNCHER_DIR)/assets/module
ANDROID_LIBS_ROOT = $(ANDROID_LAUNCHER_DIR)/libs
ANDROID_LIBS_ABI = $(ANDROID_LIBS_ROOT)/$(ANDROID_ABI)

androiddev: update
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) dev

update: all
	# Note: do not remove the module directory so there's no need
	# for `mk7z.sh` to always recreate `assets.7z` from scratch.
	rm -rfv $(ANDROID_LIBS_ROOT)
	mkdir -p $(ANDROID_ASSETS) $(ANDROID_LIBS_ABI)
	# APK version
	echo $(VERSION) > $(ANDROID_ASSETS)/version.txt
	# shared libraries are stored as raw assets
	cp -pR $(INSTALL_DIR)/koreader/libs $(ANDROID_LAUNCHER_DIR)/assets
	# in runtime luajit-launcher's libluajit.so will be loaded
	rm -vf $(ANDROID_LAUNCHER_DIR)/assets/libs/libluajit.so
	# binaries are stored as shared libraries to prevent W^X exception on Android 10+
	# https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission
	cp -pR $(INSTALL_DIR)/koreader/sdcv $(ANDROID_LIBS_ABI)/libsdcv.so
	echo "sdcv libsdcv.so" > $(ANDROID_ASSETS)/map.txt
	# assets are compressed manually and stored inside the APK.
	cd $(INSTALL_DIR)/koreader && \
		./tools/mk7z.sh \
		../../$(ANDROID_ASSETS)/koreader.7z \
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
	# make the android APK
	# Note: filter out the `--debug=…` make flag
	# so the old crummy version provided by the
	# NDK does not blow a gasket.
	MAKEFLAGS='$(filter-out --debug=%,$(MAKEFLAGS))' \
		$(MAKE) -C $(ANDROID_LAUNCHER_DIR) $(if $(KODEBUG), debug, release) \
		ANDROID_APPNAME=KOReader \
		ANDROID_VERSION=$(ANDROID_VERSION) \
		ANDROID_NAME=$(ANDROID_NAME) \
		ANDROID_FLAVOR=$(ANDROID_FLAVOR)
	cp $(ANDROID_LAUNCHER_DIR)/bin/NativeActivity.apk \
		koreader-android-$(ANDROID_ARCH)$(KODEDUG_SUFFIX)-$(VERSION).apk

PHONY += androiddev update
