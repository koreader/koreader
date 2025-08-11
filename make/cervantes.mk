CERVANTES_DIR = $(PLATFORM_DIR)/cervantes
CERVANTES_PACKAGE = koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).zip
CERVANTES_PACKAGE_OTA = koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).targz

define UPDATE_PATH_EXCLUDES +=
tools
endef

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(CERVANTES_PACKAGE)
	# Cervantes launching scripts
	$(SYMLINK) $(CERVANTES_DIR)/*.sh $(INSTALL_DIR)/koreader
	# Create packages.
	$(strip $(call mkupdate,$(CERVANTES_PACKAGE)))
	$(strip $(call mkupdate,$(CERVANTES_PACKAGE_OTA)))

PHONY += update
