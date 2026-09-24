BOOKEEN_DIR = $(PLATFORM_DIR)/bookeen

BOOKEEN_BUILD_STAMP := $(shell date -u +%Y%m%d-%H%M%S)

BOOKEEN_PACKAGE = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip
BOOKEEN_PACKAGE_OTA = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip
BOOKEEN_PACKAGE_OLD_OTA = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).targz

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

update-txz: update-prepare
	$(strip $(call mkupdate,$(BOOKEEN_PACKAGE_OTA)))

update-tgz: update-prepare
	$(strip $(call mkupdate,$(BOOKEEN_PACKAGE_OLD_OTA)))

update: update-zip update-txz update-tgz
