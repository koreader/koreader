BOOKEEN_DIR = $(PLATFORM_DIR)/bookeen

BOOKEEN_PACKAGE = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip

define UPDATE_PATH_EXCLUDES +=
tools
endef

update-prepare: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# Bookeen launching scripts
	$(SYMLINK) $(BOOKEEN_DIR)/* $(INSTALL_DIR)/koreader/

update-zip: update-prepare
	$(strip $(call mkupdate,$(BOOKEEN_PACKAGE)))

update: update-zip
