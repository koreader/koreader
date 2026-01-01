POCKETBOOK_DIR = $(PLATFORM_DIR)/pocketbook
PB_PACKAGE = koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).zip
PB_PACKAGE_OTA = koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).tar.xz
PB_PACKAGE_OLD_OTA = koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).targz

define UPDATE_PATH_EXCLUDES +=
tools
endef

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# Pocketbook launching scripts
	rm -rf $(INSTALL_DIR)/{applications,system}
	mkdir -p $(INSTALL_DIR)/applications
	mkdir -p $(INSTALL_DIR)/system/bin
	$(SYMLINK) $(POCKETBOOK_DIR)/koreader.app $(INSTALL_DIR)/applications/
	$(SYMLINK) $(POCKETBOOK_DIR)/system_koreader.app $(INSTALL_DIR)/system/bin/koreader.app
	$(SYMLINK) $(INSTALL_DIR)/koreader $(INSTALL_DIR)/applications/
	# Create packages.
	$(strip $(call mkupdate,--manifest-transform=/^system\//d $(PB_PACKAGE),applications/koreader)) applications system
	$(strip $(call mkupdate,--manifest-transform=/^system\//d $(PB_PACKAGE_OTA),applications/koreader)) applications system
	$(strip $(call mkupdate,--manifest-transform=s/^/..\// $(PB_PACKAGE_OLD_OTA),applications/koreader)) applications

PHONY += update
