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

# set PATH to find CC in managed toolchains
ifeq ($(TARGET), android)
	PATH:=$(ANDROID_TOOLCHAIN)/bin:$(PATH)
else ifeq ($(TARGET), pocketbook)
	PATH:=$(POCKETBOOK_TOOLCHAIN)/bin:$(PATH)
endif

MACHINE=$(shell PATH=$(PATH) $(CC) -dumpmachine 2>/dev/null)
ifdef KODEBUG
	MACHINE:=$(MACHINE)-debug
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
APPIMAGE_DIR=$(PLATFORM_DIR)/appimage
CERVANTES_DIR=$(PLATFORM_DIR)/cervantes
KINDLE_DIR=$(PLATFORM_DIR)/kindle
KOBO_DIR=$(PLATFORM_DIR)/kobo
POCKETBOOK_DIR=$(PLATFORM_DIR)/pocketbook
SONY_PRSTUX_DIR=$(PLATFORM_DIR)/sony-prstux
UBUNTUTOUCH_DIR=$(PLATFORM_DIR)/ubuntu-touch
UBUNTUTOUCH_SDL_DIR:=$(UBUNTUTOUCH_DIR)/ubuntu-touch-sdl
WIN32_DIR=$(PLATFORM_DIR)/win32

# appimage setup
APPIMAGETOOL=appimagetool-x86_64.AppImage
APPIMAGETOOL_URL=https://github.com/AppImage/AppImageKit/releases/download/11/appimagetool-x86_64.AppImage

# set to 1 if in Docker
DOCKER:=$(shell grep -q docker /proc/1/cgroup 2>/dev/null && echo 1)

# files to link from main directory
INSTALL_FILES=reader.lua setupkoenv.lua frontend resources defaults.lua datastorage.lua \
		l10n tools README.md COPYING

all: $(if $(ANDROID),,$(KOR_BASE)/$(OUTPUT_DIR)/luajit)
	$(MAKE) -C $(KOR_BASE)
	install -d $(INSTALL_DIR)/koreader
	rm -f $(INSTALL_DIR)/koreader/git-rev; echo "$(VERSION)" > $(INSTALL_DIR)/koreader/git-rev
ifneq ($(or $(EMULATE_READER),$(WIN32)),)
	cp -f $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/koreader/
	@echo "[*] create symlink instead of copying files in development mode"
	cd $(INSTALL_DIR)/koreader && \
		ln -sf ../../$(KOR_BASE)/$(OUTPUT_DIR)/* .
	@echo "[*] install front spec only for the emulator"
	cd $(INSTALL_DIR)/koreader/spec && test -e front || \
		ln -sf ../../../../spec ./front
	cd $(INSTALL_DIR)/koreader/spec/front/unit && test -e data || \
		ln -sf ../../test ./data
else
	$(RCP) -fL $(KOR_BASE)/$(OUTPUT_DIR)/. $(INSTALL_DIR)/koreader/.
endif
	for f in $(INSTALL_FILES); do \
		ln -sf ../../$$f $(INSTALL_DIR)/koreader/; \
	done
ifdef ANDROID
	cd $(INSTALL_DIR)/koreader && \
		ln -sf ../../$(ANDROID_DIR)/*.lua .
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
	@echo "[*] Installresources"
	$(RCP) -pL resources/fonts/. $(INSTALL_DIR)/koreader/fonts/.
	install -d $(INSTALL_DIR)/koreader/{screenshots,data/{dict,tessdata},fonts/host,ota}
ifeq ($(or $(EMULATE_READER),$(WIN32)),)
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
		--no-auto-insulate \
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
			--no-auto-insulate \
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

ZIP_EXCLUDE=-x "*.swp" -x "*.swo" -x "*.orig" -x "*.un~"
# Don't bundle launchpad on touch devices..
ifeq ($(TARGET), kindle-legacy)
KINDLE_LEGACY_LAUNCHER:=launchpad
endif
kindleupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-$(DIST)-$(MACHINE)-$(VERSION).zip
	# Kindle launching scripts
	ln -sf ../$(KINDLE_DIR)/extensions $(INSTALL_DIR)/
	ln -sf ../$(KINDLE_DIR)/launchpad $(INSTALL_DIR)/
	ln -sf ../../$(KINDLE_DIR)/koreader.sh $(INSTALL_DIR)/koreader
	ln -sf ../../$(KINDLE_DIR)/libkohelper.sh $(INSTALL_DIR)/koreader
	ln -sf ../../$(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && pwd && \
		zip -9 -r \
			../koreader-$(DIST)-$(MACHINE)-$(VERSION).zip \
			extensions koreader $(KINDLE_LEGACY_LAUNCHER) \
			-x "koreader/resources/fonts/*" "koreader/ota/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate kindleupdate package index file
	zipinfo -1 koreader-$(DIST)-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-$(DIST)-$(MACHINE)-$(VERSION).zip \
		koreader/ota/package.index
	# make gzip kindleupdate for zsync OTA update
	# note that the targz file extension is intended to keep ISP from caching
	# the file, see koreader#1644.
	cd $(INSTALL_DIR) && \
		tar -I"gzip --rsyncable" -cah --no-recursion -f ../koreader-$(DIST)-$(MACHINE)-$(VERSION).targz \
		-T koreader/ota/package.index

koboupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-kobo-$(MACHINE)-$(VERSION).zip
	# Kobo launching scripts
	cp $(KOBO_DIR)/koreader.png $(INSTALL_DIR)/koreader.png
	cp $(KOBO_DIR)/fmon/README.txt $(INSTALL_DIR)/README_kobo.txt
	cp $(KOBO_DIR)/*.sh $(INSTALL_DIR)/koreader
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-kobo-$(MACHINE)-$(VERSION).zip \
			koreader -x "koreader/resources/fonts/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate koboupdate package index file
	zipinfo -1 koreader-kobo-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-kobo-$(MACHINE)-$(VERSION).zip \
		koreader/ota/package.index koreader.png README_kobo.txt
	# make gzip koboupdate for zsync OTA update
	cd $(INSTALL_DIR) && \
		tar -I"gzip --rsyncable" -cah --no-recursion -f ../koreader-kobo-$(MACHINE)-$(VERSION).targz \
		-T koreader/ota/package.index

pbupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-pocketbook-$(MACHINE)-$(VERSION).zip
	# Pocketbook launching script
	mkdir -p $(INSTALL_DIR)/applications
	mkdir -p $(INSTALL_DIR)/system/bin
	mkdir -p $(INSTALL_DIR)/system/config

	cp $(POCKETBOOK_DIR)/koreader.app $(INSTALL_DIR)/applications
	cp $(POCKETBOOK_DIR)/koreader.app $(INSTALL_DIR)/system/bin
	cp $(POCKETBOOK_DIR)/extensions.cfg $(INSTALL_DIR)/system/config
	cp -rfL $(INSTALL_DIR)/koreader $(INSTALL_DIR)/applications
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-pocketbook-$(MACHINE)-$(VERSION).zip \
			applications -x "applications/koreader/resources/fonts/*" \
			"applications/koreader/resources/icons/src/*" "applications/koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate koboupdate package index file
	zipinfo -1 koreader-pocketbook-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	echo "applications/koreader/ota/package.index" >> \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	# hack file path when running tar in parent directory of koreader
	sed -i -e 's/^/..\//' \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -ru ../koreader-pocketbook-$(MACHINE)-$(VERSION).zip \
		applications/koreader/ota/package.index system
	# make gzip pbupdate for zsync OTA update
	cd $(INSTALL_DIR)/applications && \
		tar -I"gzip --rsyncable" -cah --no-recursion -f ../../koreader-pocketbook-$(MACHINE)-$(VERSION).targz \
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
	ln -sf ../../$(UBUNTUTOUCH_DIR)/libSDL2.so $(INSTALL_DIR)/koreader/libs

	# create new package
	cd $(INSTALL_DIR) && pwd && \
		zip -9 -r \
			../koreader-$(DIST)-$(MACHINE)-$(VERSION).zip \
			koreader -x "koreader/resources/fonts/*" "koreader/ota/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)

	# generate update package index file
	zipinfo -1 koreader-$(DIST)-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-$(DIST)-$(MACHINE)-$(VERSION).zip \
		koreader/ota/package.index
	# make gzip update for zsync OTA update
	cd $(INSTALL_DIR) && \
		tar -czah --no-recursion -f ../koreader-$(DIST)-$(MACHINE)-$(VERSION).targz \
		-T koreader/ota/package.index

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
	mkdir -p $(ANDROID_LAUNCHER_DIR)/assets/module
	-rm $(ANDROID_LAUNCHER_DIR)/assets/module/koreader-*
	# in runtime luajit-launcher's libluajit.so will be loaded
	-rm $(INSTALL_DIR)/koreader/libs/libluajit.so
	# create zip package
	cd $(INSTALL_DIR)/koreader && \
		zip -9 -r \
			../../koreader-android-$(MACHINE)-$(VERSION).zip \
			* -x "resources/fonts/*" "resources/icons/src/*" "spec/*" \
			$(ZIP_EXCLUDE)
	# generate android update package index file
	zipinfo -1 koreader-android-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	rm -f koreader-android-$(MACHINE)-$(VERSION).zip
	echo "ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	cp $(INSTALL_DIR)/koreader/git-rev $(INSTALL_DIR)/koreader/ota-rev
	# don't update the git-rev so that the next start won't revert back
	# the older 7z version in the assets
	$(ISED) '/git-rev/d' $(INSTALL_DIR)/koreader/ota/package.index
	# make gzip android update for zsync OTA update
	-cd $(INSTALL_DIR)/koreader && \
		tar -czah --no-recursion -f ../../koreader-android-$(MACHINE)-$(VERSION).targz \
		-T ota/package.index
	# make android update apk
	cd $(INSTALL_DIR)/koreader && 7z a -l -mx=1 \
		../../$(ANDROID_LAUNCHER_DIR)/assets/module/koreader-$(VERSION).7z * \
		-x!resources/fonts -x!resources/icons/src -x!spec
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) apk
	cp $(ANDROID_LAUNCHER_DIR)/bin/NativeActivity-debug.apk \
		koreader-android-$(MACHINE)-$(VERSION).apk

sony-prstuxupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any	
	rm -f koreader-sony-prstux-$(MACHINE)-$(VERSION).zip
	# Sony PRSTUX launching scripts
	cp $(SONY_PRSTUX_DIR)/*.sh $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
	        zip -9 -r \
	                ../koreader-sony-prstux-$(MACHINE)-$(VERSION).zip \
	                koreader -x "koreader/resources/fonts/*" \
	                "koreader/resources/icons/src/*" "koreader/spec/*" \
	                $(ZIP_EXCLUDE)
	# generate update package index file
	zipinfo -1 koreader-sony-prstux-$(MACHINE)-$(VERSION).zip > \
	        $(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-sony-prstux-$(MACHINE)-$(VERSION).zip \
	        koreader/ota/package.index
	# make gzip sonyprstux update for zsync OTA update
	cd $(INSTALL_DIR) && \
	        tar -I"gzip --rsyncable" -cah --no-recursion -f ../koreader-sony-prstux-$(MACHINE)-$(VERSION).targz \
	        -T koreader/ota/package.index

cervantesupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-cervantes-$(MACHINE)-$(VERSION).zip
	# Cervantes launching scripts
	cp $(CERVANTES_DIR)/*.sh $(INSTALL_DIR)/koreader
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-cervantes-$(MACHINE)-$(VERSION).zip \
			koreader -x "koreader/resources/fonts/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate update package index file
	zipinfo -1 koreader-cervantes-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-cervantes-$(MACHINE)-$(VERSION).zip \
	koreader/ota/package.index
	# make gzip cervantes update for zsync OTA update
	cd $(INSTALL_DIR) && \
	tar -I"gzip --rsyncable" -cah --no-recursion -f ../koreader-cervantes-$(MACHINE)-$(VERSION).targz \
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
else ifeq ($(TARGET), ubuntu-touch)
	make utupdate
endif

androiddev: androidupdate
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) dev

android-toolchain:
	$(MAKE) -C $(KOR_BASE) android-toolchain

pocketbook-toolchain:
	$(MAKE) -C $(KOR_BASE) pocketbook-toolchain


# for gettext
DOMAIN=koreader
TEMPLATE_DIR=l10n/templates
KOREADER_MISC_TOOL=../koreader-misc
XGETTEXT_BIN=$(KOREADER_MISC_TOOL)/gettext/lua_xgettext.py

pot:
	mkdir -p $(TEMPLATE_DIR)
	$(XGETTEXT_BIN) reader.lua `find frontend -iname "*.lua"` \
		`find plugins -iname "*.lua"` \
		`find tools -iname "*.lua"` \
		> $(TEMPLATE_DIR)/$(DOMAIN).pot
	# push source file to Transifex
	$(MAKE) -i -C l10n bootstrap
	$(MAKE) -C l10n push

po:
	$(MAKE) -i -C l10n bootstrap
	$(MAKE) -C l10n pull


static-check:
	@if which luacheck > /dev/null; then \
			luacheck -q {reader,setupkoenv,datastorage}.lua frontend plugins spec; \
		else \
			echo "[!] luacheck not found. "\
			"you can install it with 'luarocks install luacheck'"; \
		fi

doc:
	make -C doc

.PHONY: test doc
