DEBIAN_DIR = $(PLATFORM_DIR)/debian

update: all
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

.PHONY: update
