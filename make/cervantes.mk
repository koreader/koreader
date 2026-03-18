CERVANTES_DIR = $(PLATFORM_DIR)/cervantes
CERVANTES_PACKAGE = koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).zip
CERVANTES_PACKAGE_OTA = koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).targz

define UPDATE_PATH_EXCLUDES +=
tools
endef

update-prepare: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(CERVANTES_PACKAGE)
	# Cervantes launching scripts
	$(SYMLINK) $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader/spinning_zsync.sh
	$(SYMLINK) $(CERVANTES_DIR)/*.sh $(INSTALL_DIR)/koreader
	$(SYMLINK) $(CERVANTES_DIR)/spinning_zsync $(INSTALL_DIR)/koreader

update-zip: update-prepare
	$(strip $(call mkupdate,$(CERVANTES_PACKAGE)))

update-tgz: update-prepare
	$(strip $(call mkupdate,$(CERVANTES_PACKAGE_OTA)))

update: update-zip update-tgz
