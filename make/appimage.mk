APPIMAGE_DIR = $(PLATFORM_DIR)/appimage

APPIMAGETOOL = appimagetool-x86_64.AppImage
APPIMAGETOOL_URL = https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-x86_64.AppImage

update: all
	# remove old package if any
	rm -f koreader-appimage-$(MACHINE)-$(VERSION).appimage
	$(SYMLINK) $(APPIMAGE_DIR)/AppRun $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(APPIMAGE_DIR)/koreader.desktop $(INSTALL_DIR)/koreader/
	$(SYMLINK) resources/koreader.png $(INSTALL_DIR)/koreader/
	sed -e 's/%%VERSION%%/$(VERSION)/' -e 's/%%DATE%%/$(RELEASE_DATE)/' $(PLATFORM_DIR)/common/koreader.metainfo.xml >$(INSTALL_DIR)/koreader/koreader.appdata.xml
	# also copy libbsd.so.0, cf. https://github.com/koreader/koreader/issues/4627
	$(SYMLINK) /lib/x86_64-linux-gnu/libbsd.so.0 $(INSTALL_DIR)/koreader/libs/
ifeq ("$(wildcard $(APPIMAGETOOL))","")
	# download appimagetool
	wget "$(APPIMAGETOOL_URL)"
	chmod a+x "$(APPIMAGETOOL)"
endif
	cd $(INSTALL_DIR) && pwd && \
		rm -rf tmp && mkdir -p tmp && \
		cp -Lr koreader tmp && \
		rm -rf tmp/koreader/ota && \
		rm -rf tmp/koreader/resources/icons/src && \
		rm -rf tmp/koreader/spec
	# generate AppImage
	cd $(INSTALL_DIR)/tmp && \
		ARCH=x86_64 "$$OLDPWD/$(APPIMAGETOOL)" --appimage-extract-and-run koreader && \
		mv *.AppImage ../../koreader-$(DIST)-$(MACHINE)-$(VERSION).AppImage

PHONY += update
