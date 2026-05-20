LINUX_DIR = $(PLATFORM_DIR)/linux
LINUX_PACKAGE = koreader-linux-$(LINUX_ARCH)$(KODEDUG_SUFFIX)-$(VERSION).tar.xz

DIST_DIR = $(INSTALL_DIR)/dist
DIST_APPID = rocks.koreader.KOReader

GLIBC_VERSION = $(shell ldd --version | sed -n '1s/.* \([0-9.]\+\)$$/\1/p')

define mkupdate_linux
	rm -rf $1
	install -d $1/usr/lib
	# Runtime.
	cd $(INSTALL_DIR) && '$(abspath tools/mkrelease.sh)' $(abspath $1/usr/lib)/ . $(call release_excludes,koreader/)
	# Add bin launcher indirection.
	install -d $1/usr/bin
	ln -s ../lib/koreader/koreader.sh $1/usr/bin/koreader
	# Setup launcher to use ~/.config/koreader for writable storage.
	sed -i -e 's/^# export @KOREADER_FLAVOR@$$/export KO_MULTIUSER=1/' $1/usr/lib/koreader/koreader.sh
	# AppStream metadata.
	install -D -m644 $(LINUX_DIR)/koreader.metainfo.xml $1/usr/share/metainfo/$(DIST_APPID).metainfo.xml
	sed -i -e 's/%%VERSION%%/$(VERSION)/' -e 's/%%DATE%%/$(RELEASE_DATE)/' $1/usr/share/metainfo/$(DIST_APPID).metainfo.xml
	# Copyright & license information.
	install -D -m644 COPYING $(LINUX_DIR)/copyright -t $1/usr/share/doc/koreader/
	# Desktop entry.
	install -D -m644 $(LINUX_DIR)/koreader.desktop $1/usr/share/applications/$(DIST_APPID).desktop
	# Icons.
	install -D -m644 $(LINUX_DIR)/icons/256x256/koreader.png $1/usr/share/icons/hicolor/256x256/apps/$(DIST_APPID).png
	install -D -m644 $(LINUX_DIR)/icons/512x512/koreader.png $1/usr/share/icons/hicolor/512x512/apps/$(DIST_APPID).png
	install -D -m644 resources/koreader.svg $1/usr/share/icons/hicolor/scalable/apps/$(DIST_APPID).svg
	# Man page.
	install -D -m644 $(LINUX_DIR)/koreader.1 -t $1/usr/share/man/man1/
	gzip -9 $1/usr/share/man/man1/koreader.1
endef

update-txz: all
	$(call mkupdate_linux,$(INSTALL_DIR)/txz)
	# Add README.
	sed -e 's/%%VERSION%%/$(VERSION)/' \
		-e 's/%%ARCH%%/$(LINUX_ARCH)/' \
		-e 's/%%ABI%%/$(GLIBC_VERSION)/' \
		 $(LINUX_DIR)/instructions.txt >$(INSTALL_DIR)/txz/usr/README.md
	# Create the final archive.
	cd $(INSTALL_DIR)/txz/usr && $(strip $(abspath tools/mkrelease.sh) --epoch=$(RELEASE_DATE) $(if $(PARALLEL_JOBS),--jobs $(PARALLEL_JOBS)) --no-dereference $(if $(LINUX_PACKAGE_COMPRESSION),--options='$(LINUX_PACKAGE_COMPRESSION)') $(abspath $(LINUX_PACKAGE)) .)
	# Cleanup.
	rm -rf $(INSTALL_DIR)/txz

update: update-txz

include make/appimage.mk
include make/debian.mk
