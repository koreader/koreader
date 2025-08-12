REMARKABLE_DIR ?= $(PLATFORM_DIR)/remarkable
REMARKABLE_PACKAGE = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip
REMARKABLE_PACKAGE_OTA = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).targz

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
tools
endef

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# Remarkable scripts
	$(SYMLINK) $(REMARKABLE_DIR)/* $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader/
	# Create packages.
	$(strip $(call mkupdate,$(REMARKABLE_PACKAGE)))
	$(strip $(call mkupdate,$(REMARKABLE_PACKAGE_OTA)))

PHONY += update
