REMARKABLE_DIR = $(PLATFORM_DIR)/remarkable
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
	$(SYMLINK) $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(REMARKABLE_DIR)/koreader.sh $(INSTALL_DIR)/koreader/
ifeq (remarkable,$(TARGET))
	$(SYMLINK) $(REMARKABLE_DIR)/README.md $(INSTALL_DIR)/koreader/README_remarkable.md
	$(SYMLINK) $(REMARKABLE_DIR)/button-listen.service $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(REMARKABLE_DIR)/disable-wifi.sh $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(REMARKABLE_DIR)/enable-wifi.sh $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(REMARKABLE_DIR)/external.manifest.json $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(REMARKABLE_DIR)/koreader.service $(INSTALL_DIR)/koreader/
endif
ifeq (remarkable-aarch64,$(TARGET))
	$(SYMLINK) $(REMARKABLE_DIR)/README_aarch64.md $(INSTALL_DIR)/koreader/README_remarkable.md
	$(SYMLINK) $(REMARKABLE_DIR)/external.manifest_aarch64.json $(INSTALL_DIR)/koreader/external.manifest.json
endif
	# Create packages.
	$(strip $(call mkupdate,$(REMARKABLE_PACKAGE)))
	$(strip $(call mkupdate,$(REMARKABLE_PACKAGE_OTA)))

PHONY += update
