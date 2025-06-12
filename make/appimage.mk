APPIMAGE_DIR = $(PLATFORM_DIR)/appimage

APPIMAGETOOL = appimagetool-x86_64.AppImage
APPIMAGETOOL_URL = https://github.com/AppImage/appimagetool/releases/download/continuous/$(APPIMAGETOOL)

KOREADER_APPIMAGE = koreader-$(DIST)-$(MACHINE)-$(VERSION).AppImage

UBUNTU_LIBBSD = /lib/x86_64-linux-gnu/libbsd.so.0

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autofrontlight.koplugin
plugins/timesync.koplugin
$(filter-out tools/trace_require.lua tools/wbuilder.lua,$(wildcard tools/*))
endef

update: all
	cd $(INSTALL_DIR)/koreader && '$(abspath tools/mkrelease.sh)' ../appimage/ . $(release_excludes)
	cp $(APPIMAGE_DIR)/{AppRun,koreader.desktop} resources/koreader.png $(INSTALL_DIR)/appimage/
	sed -e 's/%%VERSION%%/$(VERSION)/' -e 's/%%DATE%%/$(RELEASE_DATE)/' $(PLATFORM_DIR)/common/koreader.metainfo.xml >$(INSTALL_DIR)/appimage/koreader.appdata.xml
	# Also copy libbsd.so.0 (cf. https://github.com/koreader/koreader/issues/4627).
ifeq (,$(wildcard $(UBUNTU_LIBBSD)))
	# Only warn if it's missing (e.g. when testing on a non-Ubuntu distribution).
	echo 'WARNING: not bundling missing $(UBUNTU_LIBBSD)' 1>&2
else
	cp $(UBUNTU_LIBBSD) $(INSTALL_DIR)/appimage/libs/
endif
ifeq (,$(wildcard $(APPIMAGETOOL)))
	# Download appimagetool.
	wget '$(APPIMAGETOOL_URL)'
	chmod a+x ./$(APPIMAGETOOL)
endif
	# Generate AppImage.
	ARCH=x86_64 ./$(APPIMAGETOOL) --appimage-extract-and-run $(INSTALL_DIR)/appimage $(KOREADER_APPIMAGE)

PHONY += update
