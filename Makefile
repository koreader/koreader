# koreader-base directory
KOR_BASE?=koreader-base

# the repository might not have been checked out yet, so make this
# able to fail:
-include $(KOR_BASE)/Makefile.defs

# we want VERSION to carry the version of koreader, not koreader-base
VERSION=$(shell git describe HEAD)
REVISION=$(shell git rev-parse --short HEAD)

# subdirectory we use to build the installation bundle
export PATH:=$(CURDIR)/$(KOR_BASE)/toolchain/android-toolchain/bin:$(PATH)
MACHINE?=$(shell PATH=$(PATH) $(CC) -dumpmachine 2>/dev/null)
INSTALL_DIR=koreader-$(MACHINE)

ANDROID_DIR=android
ANDROID_LAUNCHER_DIR:=$(ANDROID_DIR)/luajit-launcher

# files to link from main directory
INSTALL_FILES=reader.lua frontend resources defaults.lua l10n \
		git-rev README.md COPYING

# for gettext
DOMAIN=koreader
TEMPLATE_DIR=l10n/templates
KOREADER_MISC_TOOL=../misc
XGETTEXT_BIN=$(KOREADER_MISC_TOOL)/gettext/lua_xgettext.py


all: $(if $(ANDROID),,$(KOR_BASE)/$(OUTPUT_DIR)/luajit)
	$(MAKE) -C $(KOR_BASE)
	echo $(VERSION) > git-rev
	mkdir -p $(INSTALL_DIR)/koreader
ifdef EMULATE_READER
	cp -f $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/koreader/
	# create symlink instead of copying files in development mode
	cd $(INSTALL_DIR)/koreader && \
		ln -sf ../../$(KOR_BASE)/$(OUTPUT_DIR)/* .
	# install front spec only for the emulator
	cd $(INSTALL_DIR)/koreader/spec && test -e front || \
		ln -sf ../../../../spec ./front
	cd $(INSTALL_DIR)/koreader/spec/front/unit && test -e data || \
		ln -sf ../../test ./data
else
	cp -rfL $(KOR_BASE)/$(OUTPUT_DIR)/* $(INSTALL_DIR)/koreader/
endif
	for f in $(INSTALL_FILES); do \
		ln -sf ../../$$f $(INSTALL_DIR)/koreader/; \
	done
ifdef ANDROID
	cd $(INSTALL_DIR)/koreader && \
		ln -sf ../../$(ANDROID_DIR)/*.lua .
endif
	# install plugins
	cp -r plugins/* $(INSTALL_DIR)/koreader/plugins/
	cp -rpL resources/fonts/* $(INSTALL_DIR)/koreader/fonts/
	mkdir -p $(INSTALL_DIR)/koreader/screenshots
	mkdir -p $(INSTALL_DIR)/koreader/data/dict
	mkdir -p $(INSTALL_DIR)/koreader/data/tessdata
	mkdir -p $(INSTALL_DIR)/koreader/fonts/host
	mkdir -p $(INSTALL_DIR)/koreader/ota
ifndef EMULATE_READER
	# clean up, remove unused files for releases
	rm -rf $(INSTALL_DIR)/koreader/data/{cr3.ini,cr3skin-format.txt,desktop,devices,manual}
	rm $(INSTALL_DIR)/koreader/fonts/droid/DroidSansFallbackFull.ttf
endif

$(KOR_BASE)/$(OUTPUT_DIR)/luajit:
	$(MAKE) -C $(KOR_BASE)

$(INSTALL_DIR)/koreader/.busted:
	test -e $(INSTALL_DIR)/koreader/.busted || \
		ln -sf ../../.busted $(INSTALL_DIR)/koreader

testfront: $(INSTALL_DIR)/koreader/.busted
	cd $(INSTALL_DIR)/koreader && busted -l ./luajit

test:
	$(MAKE) -C $(KOR_BASE) test
	$(MAKE) testfront

.PHONY: test

fetchthirdparty:
	git submodule init
	git submodule sync
	git submodule update
	$(MAKE) -C $(KOR_BASE) fetchthirdparty

clean:
	rm -rf $(INSTALL_DIR)
	$(MAKE) -C $(KOR_BASE) clean

kindleupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-kindle-$(MACHINE)-$(VERSION).zip
	# Kindle launching scripts
	ln -sf ../kindle/extensions $(INSTALL_DIR)/
	ln -sf ../kindle/launchpad $(INSTALL_DIR)/
	ln -sf ../../kindle/koreader.sh $(INSTALL_DIR)/koreader
	ln -sf ../../kindle/libkohelper.sh $(INSTALL_DIR)/koreader
	ln -sf ../../kindle/kotar_cpoint $(INSTALL_DIR)/koreader
	# create new package
	# Don't bundle launchpad on touch devices..
ifeq ($(TARGET), kindle-legacy)
	KINDLE_LEGACY_LAUNCHER:=launchpad
endif
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-kindle-$(MACHINE)-$(VERSION).zip \
			extensions koreader $(KINDLE_LEGACY_LAUNCHER) \
			-x "koreader/resources/fonts/*" "koreader/ota/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*"
	# generate kindleupdate package index file
	zipinfo -1 koreader-kindle-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-kindle-$(MACHINE)-$(VERSION).zip \
		koreader/ota/package.index
	# make gzip kindleupdate for zsync OTA update
	cd $(INSTALL_DIR) && \
		tar czafh ../koreader-kindle-$(MACHINE)-$(VERSION).tar.gz \
		-T koreader/ota/package.index --no-recursion

koboupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-kobo-$(MACHINE)-$(VERSION).zip
	# Kobo launching scripts
	mkdir -p $(INSTALL_DIR)/kobo/mnt/onboard/.kobo
	ln -sf ../../../../../kobo/fmon $(INSTALL_DIR)/kobo/mnt/onboard/.kobo/
	cd $(INSTALL_DIR)/kobo && tar -czhf ../KoboRoot.tgz mnt
	cp resources/koreader.png $(INSTALL_DIR)/koreader.png
	cp kobo/fmon/README.txt $(INSTALL_DIR)/README_kobo.txt
	cp kobo/koreader.sh $(INSTALL_DIR)/koreader
	cp kobo/suspend.sh $(INSTALL_DIR)/koreader
	cp kobo/nickel.sh $(INSTALL_DIR)/koreader
	cp kobo/wifi.sh $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-kobo-$(MACHINE)-$(VERSION).zip \
			KoboRoot.tgz koreader koreader.png README_kobo.txt \
			-x "koreader/resources/fonts/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*"
	# generate koboupdate package index file
	zipinfo -1 koreader-kobo-$(MACHINE)-$(VERSION).zip > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../koreader-kobo-$(MACHINE)-$(VERSION).zip \
		koreader/ota/package.index
	# make gzip koboupdate for zsync OTA update
	cd $(INSTALL_DIR) && \
		tar czafh ../koreader-kobo-$(MACHINE)-$(VERSION).tar.gz \
		-T koreader/ota/package.index --no-recursion

androidupdate: all
	mkdir -p $(ANDROID_LAUNCHER_DIR)/assets/module
	-rm $(ANDROID_LAUNCHER_DIR)/assets/module/koreader-*
	cd $(INSTALL_DIR)/koreader && 7z a -l -mx=1 \
		../../$(ANDROID_LAUNCHER_DIR)/assets/module/koreader-g$(REVISION).7z * \
		-x!resources/fonts -x!resources/icons/src -x!spec
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) apk
	cp $(ANDROID_LAUNCHER_DIR)/bin/NativeActivity-debug.apk \
		koreader-android-$(MACHINE)-$(VERSION).apk

androiddev: androidupdate
	$(MAKE) -C $(ANDROID_LAUNCHER_DIR) dev

android-toolchain:
	$(MAKE) -C $(KOR_BASE) android-toolchain

pot:
	$(XGETTEXT_BIN) reader.lua `find frontend -iname "*.lua"` \
		`find plugins -iname "*.lua"` \
		> $(TEMPLATE_DIR)/$(DOMAIN).pot

po:
	$(MAKE) -i -C l10n bootstrap update
