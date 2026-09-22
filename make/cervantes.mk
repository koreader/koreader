CERVANTES_DIR = $(PLATFORM_DIR)/cervantes
CERVANTES_PACKAGE = koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).zip

define UPDATE_PATH_EXCLUDES +=
tools
endef

update-prepare: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(CERVANTES_PACKAGE)
	# Cervantes launching scripts
	$(SYMLINK) $(CERVANTES_DIR)/*.sh $(INSTALL_DIR)/koreader

update-zip: update-prepare
	$(strip $(call mkupdate,$(CERVANTES_PACKAGE)))

update: update-zip
