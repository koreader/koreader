KOBO_DIR = $(PLATFORM_DIR)/kobo
KOBO_PACKAGE = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip
KOBO_PACKAGE_OTA = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).targz

define UPDATE_PATH_EXCLUDES +=
$(filter-out tools/kobo%,$(wildcard tools/*))
endef

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# Kobo launching scripts
	$(SYMLINK) $(KOBO_DIR)/koreader.png $(INSTALL_DIR)/
	$(SYMLINK) $(KOBO_DIR)/*.sh $(INSTALL_DIR)/koreader/
	# Create packages.
	$(strip $(call mkupdate,--manifest-transform=/^koreader\.png$$/d $(KOBO_PACKAGE))) koreader.png
	$(strip $(call mkupdate,$(KOBO_PACKAGE_OTA)))

PHONY += update
