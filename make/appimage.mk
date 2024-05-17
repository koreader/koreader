APPIMAGE_DIR = $(PLATFORM_DIR)/appimage

APPIMAGETOOL = appimagetool-x86_64.AppImage
APPIMAGETOOL_URL = https://github.com/AppImage/AppImageKit/releases/download/13/appimagetool-x86_64.AppImage

update: all
	# remove old package if any
	rm -f koreader-appimage-$(MACHINE)-$(VERSION).appimage
	$(SYMLINK) $(abspath $(APPIMAGE_DIR)/AppRun) $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(abspath $(APPIMAGE_DIR)/koreader.desktop) $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(abspath resources/koreader.png) $(INSTALL_DIR)/koreader/
    sed -e 's/%%VERSION%%/$(VERSION)/' -e 's/%%DATE%%/$(RELEASE_DATE)/' $(APPIMAGE_DIR)/koreader.appdata.xml >$(INSTALL_DIR)/koreader/koreader.appdata.xml
	# TODO at best this is DebUbuntu specific
	$(SYMLINK) /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0 $(INSTALL_DIR)/koreader/libs/libSDL2.so
	# required for our stock Ubuntu SDL even though we don't use sound
	# the readlink is a half-hearted attempt at being generic; the echo libsndio.so.7.0 is specific to the nightly builds
	$(SYMLINK) /usr/lib/x86_64-linux-gnu/$(shell readlink /usr/lib/x86_64-linux-gnu/libsndio.so || echo libsndio.so.7.0) $(INSTALL_DIR)/koreader/libs/
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

.PHONY: update
