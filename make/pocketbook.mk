POCKETBOOK_DIR = $(PLATFORM_DIR)/pocketbook
PB_PACKAGE = koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).zip
PB_PACKAGE_OTA = koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).tar.xz
PB_PACKAGE_OLD_OTA = koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).targz

define UPDATE_PATH_EXCLUDES +=
tools
endef

# We install into a hidden ".koreader" directory so PocketBook's built-in
# library scanner ignores our fonts, help documents and crash.log instead of
# indexing them as books (koreader/koreader#15462). The release tooling strips
# dotfiles by default (-xr!.*), which would otherwise drop our own directory
# back out of the package, so lift that blanket rule for this platform only.
UPDATE_GLOBAL_EXCLUDES := $(filter-out .*,$(UPDATE_GLOBAL_EXCLUDES))

update-prepare: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# Pocketbook launching scripts
	rm -rf $(INSTALL_DIR)/{applications,system}
	mkdir -p $(INSTALL_DIR)/applications
	mkdir -p $(INSTALL_DIR)/system/bin
	$(SYMLINK) $(POCKETBOOK_DIR)/koreader.app $(INSTALL_DIR)/applications/
	$(SYMLINK) $(POCKETBOOK_DIR)/system_koreader.app $(INSTALL_DIR)/system/bin/koreader.app
	$(SYMLINK) $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(INSTALL_DIR)/koreader $(INSTALL_DIR)/applications/.koreader

update-zip: update-prepare
	$(strip $(call mkupdate,--manifest-transform=/^system\//d $(PB_PACKAGE),applications/.koreader)) applications system

update-txz: update-prepare
	$(strip $(call mkupdate,--manifest-transform=/^system\//d $(PB_PACKAGE_OTA),applications/.koreader)) applications system

update-tgz: update-prepare
	$(strip $(call mkupdate,--manifest-transform=s/^/..\// $(PB_PACKAGE_OLD_OTA),applications/.koreader)) applications

update: update-zip update-txz update-tgz
