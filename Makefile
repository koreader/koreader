# koreader-base directory
KOR_BASE?=base

# the repository might not have been checked out yet, so make this
# able to fail:
-include $(KOR_BASE)/Makefile.defs

# We want VERSION to carry the version of the KOReader main repo, not that of koreader-base
VERSION:=$(shell git describe HEAD)
# Only append date if we're not on a whole version, like v2018.11
ifneq (,$(findstring -,$(VERSION)))
	VERSION:=$(VERSION)_$(shell git describe HEAD | xargs git show -s --format=format:"%cd" --date=short)
endif

# releases do not contain tests and misc data
IS_RELEASE := $(if $(or $(EMULATE_READER),$(WIN32)),,1)
IS_RELEASE := $(if $(or $(IS_RELEASE),$(APPIMAGE),$(DEBIAN),$(MACOS)),1,)

ANDROID_ARCH?=arm
ifeq ($(ANDROID_ARCH), x86)
	ANDROID_ABI:=$(ANDROID_ARCH)
endif
ANDROID_ABI?=armeabi-v7a

# Use the git commit count as the (integer) Android version code
ANDROID_VERSION?=$(shell git rev-list --count HEAD)
ANDROID_NAME?=$(VERSION)

# set PATH to find CC in managed toolchains
ifeq ($(TARGET), android)
	PATH:=$(ANDROID_TOOLCHAIN)/bin:$(PATH)
endif

MACHINE=$(shell PATH='$(PATH)' $(CC) -dumpmachine 2>/dev/null)
ifdef KODEBUG
	MACHINE:=$(MACHINE)-debug
	KODEDUG_SUFFIX:=-debug
endif

ifdef TARGET
	DIST:=$(TARGET)
else
	DIST:=emulator
endif

INSTALL_DIR=koreader-$(DIST)-$(MACHINE)

# platform directories
PLATFORM_DIR=platform
COMMON_DIR=$(PLATFORM_DIR)/common
ANDROID_DIR=$(PLATFORM_DIR)/android
ANDROID_LAUNCHER_DIR:=$(ANDROID_DIR)/luajit-launcher
ANDROID_ASSETS:=$(ANDROID_LAUNCHER_DIR)/assets/module
ANDROID_LIBS_ROOT:=$(ANDROID_LAUNCHER_DIR)/libs
ANDROID_LIBS_ABI:=$(ANDROID_LIBS_ROOT)/$(ANDROID_ABI)
APPIMAGE_DIR=$(PLATFORM_DIR)/appimage
CERVANTES_DIR=$(PLATFORM_DIR)/cervantes
DEBIAN_DIR=$(PLATFORM_DIR)/debian
KINDLE_DIR=$(PLATFORM_DIR)/kindle
KOBO_DIR=$(PLATFORM_DIR)/kobo
MACOS_DIR=$(PLATFORM_DIR)/mac
POCKETBOOK_DIR=$(PLATFORM_DIR)/pocketbook
REMARKABLE_DIR=$(PLATFORM_DIR)/remarkable
SONY_PRSTUX_DIR=$(PLATFORM_DIR)/sony-prstux
UBUNTUTOUCH_DIR=$(PLATFORM_DIR)/ubuntu-touch
UBUNTUTOUCH_SDL_DIR:=$(UBUNTUTOUCH_DIR)/ubuntu-touch-sdl
WIN32_DIR=$(PLATFORM_DIR)/win32

# appimage setup
APPIMAGETOOL=appimagetool-x86_64.AppImage
APPIMAGETOOL_URL=https://github.com/AppImage/AppImageKit/releases/download/12/appimagetool-x86_64.AppImage

# set to 1 if in Docker
DOCKER:=$(shell grep -q docker /proc/1/cgroup 2>/dev/null && echo 1)

# files to link from main directory
INSTALL_FILES=reader.lua setupkoenv.lua frontend resources defaults.lua datastorage.lua \
		l10n tools README.md COPYING

all: $(if $(ANDROID),,$(KOR_BASE)/$(OUTPUT_DIR)/luajit)
	$(MAKE) -C $(KOR_BASE)
	install -d $(INSTALL_DIR)/koreader
	rm -f $(INSTALL_DIR)/koreader/git-rev; echo "$(VERSION)" > $(INSTALL_DIR)/koreader/git-rev
ifdef ANDROID
	rm -f android-fdroid-version; echo -e "$(ANDROID_NAME)\n$(ANDROID_VERSION)" > koreader-android-fdroid-latest
endif
ifeq ($(IS_RELEASE),1)
	$(RCP) -fL $(KOR_BASE)/$(OUTPUT_DIR)/. $(INSTALL_DIR)/koreader/.
else
	cp -f $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/koreader/
	@echo "[*] create symlink instead of copying files in development mode"
	cd $(INSTALL_DIR)/koreader && \
		bash -O extglob -c "ln -sf ../../$(KOR_BASE)/$(OUTPUT_DIR)/!(cache) ."
	@echo "[*] install front spec only for the emulator"
	cd $(INSTALL_DIR)/koreader/spec && test -e front || \
		ln -sf ../../../../spec ./front
	cd $(INSTALL_DIR)/koreader/spec/front/unit && test -e data || \
		ln -sf ../../test ./data
endif
	for f in $(INSTALL_FILES); do \
		ln -sf ../../$$f $(INSTALL_DIR)/koreader/; \
	done
ifdef ANDROID
	cd $(INSTALL_DIR)/koreader && \
		ln -sf ../../$(ANDROID_DIR)/*.lua .
	@echo "[*] Install afterupdate marker"
	@echo "# If this file is here, there are no afterupdate scripts in /sdcard/koreader/scripts/afterupdate." > $(INSTALL_DIR)/koreader/afterupdate.marker
endif
ifdef WIN32
	@echo "[*] Install runtime libraries for win32..."
	cd $(INSTALL_DIR)/koreader && cp ../../$(WIN32_DIR)/*.dll .
endif
	@echo "[*] Install plugins"
	@# TODO: link istead of cp?
	$(RCP) plugins/. $(INSTALL_DIR)/koreader/plugins/.
	@# purge deleted plugins
	for d in $$(ls $(INSTALL_DIR)/koreader/plugins); do \
		test -d plugins/$$d || rm -rf $(INSTALL_DIR)/koreader/plugins/$$d ; done
	@echo "[*] Install resources"
	$(RCP) -pL resources/fonts/. $(INSTALL_DIR)/koreader/fonts/.
	install -d $(INSTALL_DIR)/koreader/{screenshots,data/{dict,tessdata},fonts/host,ota}
ifeq ($(IS_RELEASE),1)
	@echo "[*] Clean up, remove unused files for releases"
	rm -rf $(INSTALL_DIR)/koreader/data/{cr3.ini,cr3skin-format.txt,desktop,devices,manual}
endif

$(KOR_BASE)/$(OUTPUT_DIR)/luajit:
	$(MAKE) -C $(KOR_BASE)

$(INSTALL_DIR)/koreader/.busted: .busted
	ln -sf ../../.busted $(INSTALL_DIR)/koreader

$(INSTALL_DIR)/koreader/.luacov:
	test -e $(INSTALL_DIR)/koreader/.luacov || \
		ln -sf ../../.luacov $(INSTALL_DIR)/koreader

testfront: $(INSTALL_DIR)/koreader/.busted
	# sdr files may have unexpected impact on unit testing
	-rm -rf spec/unit/data/*.sdr
	cd $(INSTALL_DIR)/koreader && ./luajit $(shell which busted) \
		--sort-files \
		--output=gtest \
		--exclude-tags=notest $(BUSTED_OVERRIDES) $(BUSTED_SPEC_FILE)

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

fetchthirdparty:
	git submodule init
	git submodule sync
	git submodule update
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

KINDLE_PACKAGE:=koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip
KINDLE_PACKAGE_OTA:=koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).targz
ZIP_EXCLUDE=-x "*.swp" -x "*.swo" -x "*.orig" -x "*.un~"
# Don't bundle launchpad on touch devices..
ifeq ($(TARGET), kindle-legacy)
KINDLE_LEGACY_LAUNCHER:=launchpad
endif
kindleupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f $(KINDLE_PACKAGE)
	# Kindle launching scripts
	ln -sf ../$(KINDLE_DIR)/extensions $(INSTALL_DIR)/
	ln -sf ../$(KINDLE_DIR)/launchpad $(INSTALL_DIR)/
	ln -sf ../../$(KINDLE_DIR)/koreader.sh $(INSTALL_DIR)/koreader
	ln -sf ../../$(KINDLE_DIR)/libkohelper.sh $(INSTALL_DIR)/koreader
	ln -sf ../../../../../$(KINDLE_DIR)/libkohelper.sh $(INSTALL_DIR)/extensions/koreader/bin
	ln -sf ../../$(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	ln -sf ../../$(KINDLE_DIR)/wmctrl $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && pwd && \
		zip -9 -r \
			../$(KINDLE_PACKAGE) \
			extensions koreader $(KINDLE_LEGACY_LAUNCHER) \
			-x "koreader/resources/fonts/*" "koreader/ota/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate kindleupdate package index file
	zipinfo -1 $(KINDLE_PACKAGE) > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(KINDLE_PACKAGE) \
		koreader/ota/package.index
	# make gzip kindleupdate for zsync OTA update
	# note that the targz file extension is intended to keep ISP from caching
	# the file, see koreader#1644.
	cd $(INSTALL_DIR) && \
		tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../$(KINDLE_PACKAGE_OTA) \
		-T koreader/ota/package.index

KOBO_PACKAGE:=koreader-kobo$(KODEDUG_SUFFIX)-$(VERSION).zip
KOBO_PACKAGE_OTA:=koreader-kobo$(KODEDUG_SUFFIX)-$(VERSION).targz
koboupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f $(KOBO_PACKAGE)
	# Kobo launching scripts
	cp $(KOBO_DIR)/koreader.png $(INSTALL_DIR)/koreader.png
	cp $(KOBO_DIR)/fmon/README.txt $(INSTALL_DIR)/README_kobo.txt
	cp $(KOBO_DIR)/*.sh $(INSTALL_DIR)/koreader
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../$(KOBO_PACKAGE) \
			koreader -x "koreader/resources/fonts/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate koboupdate package index file
	zipinfo -1 $(KOBO_PACKAGE) > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(KOBO_PACKAGE) \
		koreader/ota/package.index koreader.png README_kobo.txt
	# make gzip koboupdate for zsync OTA update
	cd $(INSTALL_DIR) && \
		tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../$(KOBO_PACKAGE_OTA) \
		-T koreader/ota/package.index

PB_PACKAGE:=koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).zip
PB_PACKAGE_OTA:=koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).targz
pbupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f $(PB_PACKAGE)
	# Pocketbook launching scripts
	mkdir -p $(INSTALL_DIR)/applications
	mkdir -p $(INSTALL_DIR)/system/bin
	cp $(POCKETBOOK_DIR)/koreader.app $(INSTALL_DIR)/applications
	cp $(POCKETBOOK_DIR)/system_koreader.app $(INSTALL_DIR)/system/bin/koreader.app
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	cp -rfL $(INSTALL_DIR)/koreader $(INSTALL_DIR)/applications
	find $(INSTALL_DIR)/applications/koreader \
		-type f \( -name "*.gif" -o -name "*.html" -o -name "*.md" -o -name "*.txt" \) \
		-exec rm -vf {} \;
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../$(PB_PACKAGE) \
			applications -x "applications/koreader/resources/fonts/*" \
			"applications/koreader/resources/icons/src/*" "applications/koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate koboupdate package index file
	zipinfo -1 $(PB_PACKAGE) > \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	echo "applications/koreader/ota/package.index" >> \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	# hack file path when running tar in parent directory of koreader
	sed -i -e 's/^/..\//' \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -ru ../$(PB_PACKAGE) \
		applications/koreader/ota/package.index system
	# make gzip pbupdate for zsync OTA update
	cd $(INSTALL_DIR)/applications && \
		tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../../$(PB_PACKAGE_OTA) \
		-T koreader/ota/package.index

utupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-ubuntu-touch-$(MACHINE)-$(VERSION).click

	ln -sf ../../$(UBUNTUTOUCH_DIR)/koreader.sh $(INSTALL_DIR)/koreader
	ln -sf ../../$(UBUNTUTOUCH_DIR)/manifest.json $(INSTALL_DIR)/koreader
	ln -sf ../../$(UBUNTUTOUCH_DIR)/koreader.apparmor $(INSTALL_DIR)/koreader
	ln -sf ../../$(UBUNTUTOUCH_DIR)/koreader.apparmor.openstore $(INSTALL_DIR)/koreader
	ln -sf ../../$(UBUNTUTOUCH_DIR)/koreader.desktop $(INSTALL_DIR)/koreader
	ln -sf ../../$(UBUNTUTOUCH_DIR)/koreader.png $(INSTALL_DIR)/koreader
	ln -sf ../../../$(UBUNTUTOUCH_DIR)/libSDL2.so $(INSTALL_DIR)/koreader/libs

	# create new package
	cd $(INSTALL_DIR) && pwd && \
		zip -9 -r \
			../koreader-$(DIST)-$(MACHINE)-$(VERSION).zip \
			koreader -x "koreader/resources/fonts/*" "koreader/ota/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)

	# generate ubuntu touch click package
	rm -rf $(INSTALL_DIR)/tmp && mkdir -p $(INSTALL_DIR)/tmp
	cd $(INSTALL_DIR)/tmp && \
		unzip ../../koreader-$(DIST)-$(MACHINE)-$(VERSION).zip && \
		click build koreader && \
		mv *.click ../../koreader-$(DIST)-$(MACHINE)-$(VERSION).click

appimageupdate: all
	# remove old package if any
	rm -f koreader-appimage-$(MACHINE)-$(VERSION).appimage

	ln -sf ../../$(APPIMAGE_DIR)/AppRun $(INSTALL_DIR)/koreader
	ln -sf ../../$(APPIMAGE_DIR)/koreader.appdata.xml $(INSTALL_DIR)/koreader
	ln -sf ../../$(APPIMAGE_DIR)/koreader.desktop $(INSTALL_DIR)/koreader
	ln -sf ../../resources/koreader.png $(INSTALL_DIR)/koreader
	# TODO at best this is DebUbuntu specific
	ln -sf /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0 $(INSTALL_DIR)/koreader/libs/libSDL2.so
	# required for our stock Ubuntu SDL even though we don't use sound
	# the readlink is a half-hearted attempt at being generic; the echo libsndio.so.6.1 is specific to the nightly builds
	ln -sf /usr/lib/x86_64-linux-gnu/$(shell readlink /usr/lib/x86_64-linux-gnu/libsndio.so || echo libsndio.so.6.1) $(INSTALL_DIR)/koreader/libs/
	# also copy libbsd.so.0, cf. https://github.com/koreader/koreader/issues/4627
	ln -sf /lib/x86_64-linux-gnu/libbsd.so.0 $(INSTALL_DIR)/koreader/libs/
ifeq ("$(wildcard $(APPIMAGETOOL))","")
	# download appimagetool
	wget "$(APPIMAGETOOL_URL)"
	chmod a+x "$(APPIMAGETOOL)"
endif
ifeq ($(DOCKER), 1)
	# remove previously extracted appimagetool, if any
	rm -rf squashfs-root
	./$(APPIMAGETOOL) --appimage-extract
endif
	cd $(INSTALL_DIR) && pwd && \
		rm -rf tmp && mkdir -p tmp && \
		cp -Lr koreader tmp && \
		rm -rf tmp/koreader/ota && \
		rm -rf tmp/koreader/resources/icons/src && \
		rm -rf tmp/koreader/spec

	# generate AppImage
	cd $(INSTALL_DIR)/tmp && \
		ARCH=x86_64 ../../$(if $(DOCKER),squashfs-root/AppRun,$(APPIMAGETOOL)) koreader && \
		mv *.AppImage ../../koreader-$(DIST)-$(MACHINE)-$(VERSION).AppImage

androidupdate: all
	# in runtime luajit-launcher's libluajit.so will be loaded
	-rm $(INSTALL_DIR)/koreader/libs/libluajit.so

        # fresh APK assets
	rm -rfv $(ANDROID_ASSETS) $(ANDROID_LIBS_ROOT)
	mkdir -p $(ANDROID_ASSETS) $(ANDROID_LIBS_ABI)

	# APK version
	echo $(VERSION) > $(ANDROID_ASSETS)/version.txt

	# shared libraries are stored as raw assets
	cp -pR $(INSTALL_DIR)/koreader/libs $(ANDROID_LAUNCHER_DIR)/assets

	# binaries are stored as shared libraries to prevent W^X exception on Android 10+
	# https://developer.android.com/about/versions/10/behavior-changes-10#execute-permission
	cp -pR $(INSTALL_DIR)/koreader/sdcv $(ANDROID_LIBS_ABI)/libsdcv.so
	echo "sdcv libsdcv.so" > $(ANDROID_ASSETS)/map.txt

	# assets are compressed manually and stored inside the APK.
	cd $(INSTALL_DIR)/koreader && 7z a -l -m0=lzma2 -mx=9 \
		../../$(ANDROID_ASSETS)/koreader.7z * \
		-xr!*cache$ \
		-xr!*clipboard$ \
		-xr!*data/dict$ \
		-xr!*data/tessdata$ \
		-xr!*history$ \
		-xr!*l10n/templates$ \
		-xr!*libs$ \
		-xr!*ota$ \
		-xr!*resources/fonts* \
		-xr!*resources/icons/src* \
		-xr!*rocks/bin$ \
		-xr!*rocks/lib/luarocks$ \
		-xr!*screenshots$ \
		-xr!*share/man* \
		-xr!*spec$ \
		-xr!*tools$ \
		-xr!*COPYING$ \
		-xr!*Makefile$ \
		-xr!*NOTES.txt$ \
		-xr!*NOTICE$ \
		-xr!*README.md$ \
		-xr!*sdcv \
		-xr'!.*'

	# make the android APK
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) $(if $(KODEBUG), debug, release) \
		ANDROID_APPNAME=KOReader \
		ANDROID_VERSION=$(ANDROID_VERSION) \
		ANDROID_NAME=$(ANDROID_NAME) \
		ANDROID_FLAVOR=$(ANDROID_FLAVOR)

	cp $(ANDROID_LAUNCHER_DIR)/bin/NativeActivity.apk \
		koreader-android-$(ANDROID_ARCH)$(KODEDUG_SUFFIX)-$(VERSION).apk

debianupdate: all
	mkdir -pv \
		$(INSTALL_DIR)/debian/usr/bin \
		$(INSTALL_DIR)/debian/usr/lib \
		$(INSTALL_DIR)/debian/usr/share/pixmaps \
		$(INSTALL_DIR)/debian/usr/share/applications \
		$(INSTALL_DIR)/debian/usr/share/doc/koreader \
		$(INSTALL_DIR)/debian/usr/share/man/man1

	cp -pv resources/koreader.png $(INSTALL_DIR)/debian/usr/share/pixmaps
	cp -pv $(DEBIAN_DIR)/koreader.desktop $(INSTALL_DIR)/debian/usr/share/applications
	cp -pv $(DEBIAN_DIR)/copyright COPYING $(INSTALL_DIR)/debian/usr/share/doc/koreader
	cp -pv $(DEBIAN_DIR)/koreader.sh $(INSTALL_DIR)/debian/usr/bin/koreader
	cp -Lr $(INSTALL_DIR)/koreader $(INSTALL_DIR)/debian/usr/lib

	gzip -cn9 $(DEBIAN_DIR)/changelog > $(INSTALL_DIR)/debian/usr/share/doc/koreader/changelog.Debian.gz
	gzip -cn9 $(DEBIAN_DIR)/koreader.1 > $(INSTALL_DIR)/debian/usr/share/man/man1/koreader.1.gz

	chmod 644 \
		$(INSTALL_DIR)/debian/usr/share/doc/koreader/changelog.Debian.gz \
		$(INSTALL_DIR)/debian/usr/share/doc/koreader/copyright \
		$(INSTALL_DIR)/debian/usr/share/man/man1/koreader.1.gz

	rm -rf \
		$(INSTALL_DIR)/debian/usr/lib/koreader/{ota,cache,clipboard,screenshots,spec,tools,resources/fonts,resources/icons/src}

macosupdate: all
	mkdir -p \
		$(INSTALL_DIR)/bundle/Contents/MacOS \
		$(INSTALL_DIR)/bundle/Contents/Resources

	cp -pv $(MACOS_DIR)/koreader.icns $(INSTALL_DIR)/bundle/Contents/Resources/icon.icns
	cp -LR $(INSTALL_DIR)/koreader $(INSTALL_DIR)/bundle/Contents
	cp -pRv $(MACOS_DIR)/menu.xml $(INSTALL_DIR)/bundle/Contents/MainMenu.xib
	ibtool --compile "$(INSTALL_DIR)/bundle/Contents/Resources/Base.lproj/MainMenu.nib" "$(INSTALL_DIR)/bundle/Contents/MainMenu.xib"
	rm -rfv "$(INSTALL_DIR)/bundle/Contents/MainMenu.xib"

REMARKABLE_PACKAGE:=koreader-remarkable$(KODEDUG_SUFFIX)-$(VERSION).zip
REMARKABLE_PACKAGE_OTA:=koreader-remarkable$(KODEDUG_SUFFIX)-$(VERSION).targz
remarkableupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f $(REMARKABLE_PACKAGE)
	# Remarkable scripts
	cp $(REMARKABLE_DIR)/* $(INSTALL_DIR)/koreader
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
	        zip -9 -r \
	                ../$(REMARKABLE_PACKAGE) \
	                koreader -x "koreader/resources/fonts/*" \
	                "koreader/resources/icons/src/*" "koreader/spec/*" \
	                $(ZIP_EXCLUDE)
	# generate update package index file
	zipinfo -1 $(REMARKABLE_PACKAGE) > \
	        $(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(REMARKABLE_PACKAGE) \
	        koreader/ota/package.index
	# make gzip remarkable update for zsync OTA update
	cd $(INSTALL_DIR) && \
	        tar -I"gzip --rsyncable" -cah --no-recursion -f ../$(REMARKABLE_PACKAGE_OTA) \
	        -T koreader/ota/package.index

SONY_PRSTUX_PACKAGE:=koreader-sony-prstux$(KODEDUG_SUFFIX)-$(VERSION).zip
SONY_PRSTUX_PACKAGE_OTA:=koreader-sony-prstux$(KODEDUG_SUFFIX)-$(VERSION).targz
sony-prstuxupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f $(SONY_PRSTUX_PACKAGE)
	# Sony PRSTUX launching scripts
	cp $(SONY_PRSTUX_DIR)/*.sh $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
	        zip -9 -r \
	                ../$(SONY_PRSTUX_PACKAGE) \
	                koreader -x "koreader/resources/fonts/*" \
	                "koreader/resources/icons/src/*" "koreader/spec/*" \
	                $(ZIP_EXCLUDE)
	# generate update package index file
	zipinfo -1 $(SONY_PRSTUX_PACKAGE) > \
	        $(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(SONY_PRSTUX_PACKAGE) \
	        koreader/ota/package.index
	# make gzip sonyprstux update for zsync OTA update
	cd $(INSTALL_DIR) && \
	        tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../$(SONY_PRSTUX_PACKAGE_OTA) \
	        -T koreader/ota/package.index

CERVANTES_PACKAGE:=koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).zip
CERVANTES_PACKAGE_OTA:=koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).targz
cervantesupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f $(CERVANTES_PACKAGE)
	# Cervantes launching scripts
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader/spinning_zsync.sh
	cp $(CERVANTES_DIR)/*.sh $(INSTALL_DIR)/koreader
	cp $(CERVANTES_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../$(CERVANTES_PACKAGE) \
			koreader -x "koreader/resources/fonts/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate update package index file
	zipinfo -1 $(CERVANTES_PACKAGE) > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(CERVANTES_PACKAGE) \
	koreader/ota/package.index
	# make gzip cervantes update for zsync OTA update
	cd $(INSTALL_DIR) && \
	tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../$(CERVANTES_PACKAGE_OTA) \
	-T koreader/ota/package.index

update:
ifeq ($(TARGET), android)
	make androidupdate
else ifeq ($(TARGET), appimage)
	make appimageupdate
else ifeq ($(TARGET), cervantes)
	make cervantesupdate
else ifeq ($(TARGET), kindle)
	make kindleupdate
else ifeq ($(TARGET), kindle-legacy)
	make kindleupdate
else ifeq ($(TARGET), kindlepw2)
	make kindleupdate
else ifeq ($(TARGET), kobo)
	make koboupdate
else ifeq ($(TARGET), pocketbook)
	make pbupdate
else ifeq ($(TARGET), sony-prstux)
	make sony-prstuxupdate
else ifeq ($(TARGET), remarkable)
	make remarkableupdate
else ifeq ($(TARGET), ubuntu-touch)
	make utupdate
else ifeq ($(TARGET), debian)
	make debianupdate
	$(CURDIR)/platform/debian/do_debian_package.sh $(INSTALL_DIR)
else ifeq ($(TARGET), debian-armel)
	make debianupdate
	$(CURDIR)/platform/debian/do_debian_package.sh $(INSTALL_DIR) armel
else ifeq ($(TARGET), debian-armhf)
	make debianupdate
	$(CURDIR)/platform/debian/do_debian_package.sh $(INSTALL_DIR) armhf
else ifeq ($(TARGET), debian-arm64)
	make debianupdate
	$(CURDIR)/platform/debian/do_debian_package.sh $(INSTALL_DIR) arm64
else ifeq ($(TARGET), macos)
	make macosupdate
	$(CURDIR)/platform/mac/do_mac_bundle.sh $(INSTALL_DIR)
endif

androiddev: androidupdate
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) dev

android-toolchain:
	$(MAKE) -C $(KOR_BASE) android-toolchain


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

.PHONY: all clean doc test update
