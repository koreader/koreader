APPIMAGE_DIR = $(PLATFORM_DIR)/appimage

APPIMAGETOOL = appimagetool-$(APPIMAGE_ARCH).AppImage
APPIMAGETOOL_URL = https://github.com/AppImage/appimagetool/releases/download/continuous/$(APPIMAGETOOL)

APPID = rocks.koreader.koreader
APPDIR = $(INSTALL_DIR)/appimage
DESKTOP = usr/share/applications/$(APPID).desktop
METAINFO = usr/share/metainfo/$(APPID).appdata.xml

KOREADER_APPIMAGE = koreader-$(DIST)-$(APPIMAGE_ARCH)-$(VERSION).AppImage

UBUNTU_LIBBSD = /lib/$(TARGET_MACHINE)/libbsd.so.0

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autofrontlight.koplugin
plugins/timesync.koplugin
$(filter-out tools/trace_require.lua tools/wbuilder.lua,$(wildcard tools/*))
endef

appimagetool $(APPIMAGETOOL):
	wget -O $(APPIMAGETOOL).part '$(APPIMAGETOOL_URL)'
	# Zero-out AppImage magic bytes from the ELF header extended ABI version so
	# binfmt+qemu can be used (e.g. when executed from `docker run --platform …`).
	# Cf. https://github.com/AppImage/AppImageKit/issues/1056.
	printf '\0\0\0' | dd conv=notrunc obs=1 seek=8 of=$(APPIMAGETOOL).part
	chmod +x ./$(APPIMAGETOOL).part
	mv $(APPIMAGETOOL).part $(APPIMAGETOOL)

update: all $(APPIMAGETOOL)
	cd $(INSTALL_DIR)/koreader && '$(abspath tools/mkrelease.sh)' $(abspath $(APPDIR))/ . $(release_excludes)
	# Launcher.
	install -D $(APPIMAGE_DIR)/AppRun $(APPDIR)/
	# Icon.
	install -D resources/koreader.png $(APPDIR)/
	ln -s koreader.png $(APPDIR)/.DirIcon
	# Desktop entry.
	install -D $(APPIMAGE_DIR)/koreader.desktop $(APPDIR)/$(DESKTOP)
	ln -s $(DESKTOP) $(APPDIR)/$(notdir $(DESKTOP))
	# AppStream metadata.
	install -D $(PLATFORM_DIR)/common/koreader.metainfo.xml $(APPDIR)/$(METAINFO)
	sed -i -e 's/%%VERSION%%/$(VERSION)/' -e 's/%%DATE%%/$(RELEASE_DATE)/' $(APPDIR)/$(METAINFO)
	# Also copy libbsd.so.0 (cf. https://github.com/koreader/koreader/issues/4627).
ifeq (,$(wildcard $(UBUNTU_LIBBSD)))
	# Only warn if it's missing (e.g. when testing on a non-Ubuntu distribution).
	echo 'WARNING: not bundling missing $(UBUNTU_LIBBSD)' 1>&2
else
	install $(UBUNTU_LIBBSD) $(APPDIR)/libs/
endif
	# Generate AppImage.
	ARCH='$(APPIMAGE_ARCH)' ./$(APPIMAGETOOL) --appimage-extract-and-run $(APPDIR) $(KOREADER_APPIMAGE)

PHONY += appimagetool update
SOUND += $(APPIMAGETOOL)
