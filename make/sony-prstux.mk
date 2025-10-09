SONY_PRSTUX_DIR = $(PLATFORM_DIR)/sony-prstux
SONY_PRSTUX_PACKAGE = koreader-sony-prstux$(KODEDUG_SUFFIX)-$(VERSION).zip
SONY_PRSTUX_PACKAGE_OTA = koreader-sony-prstux$(KODEDUG_SUFFIX)-$(VERSION).tar.xz
SONY_PRSTUX_PACKAGE_OLD_OTA = koreader-sony-prstux$(KODEDUG_SUFFIX)-$(VERSION).targz

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
tools
endef

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# Sony PRSTUX launching scripts
	$(SYMLINK) $(SONY_PRSTUX_DIR)/*.sh $(INSTALL_DIR)/koreader
	# Create packages.
	$(strip $(call mkupdate,$(SONY_PRSTUX_PACKAGE)))
	$(strip $(call mkupdate,$(SONY_PRSTUX_PACKAGE_OTA)))
	$(strip $(call mkupdate,$(SONY_PRSTUX_PACKAGE_OLD_OTA)))

PHONY += update
