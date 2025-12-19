KINDLE_DIR = $(PLATFORM_DIR)/kindle
KINDLE_PACKAGE = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip
KINDLE_PACKAGE_OTA = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).tar.xz
# Note: the targz extension is intended to keep ISP from caching the file (Cf. koreader#1644).
KINDLE_PACKAGE_OLD_OTA = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).targz

# Don't bundle launchpad on touch devices..
ifeq ($(TARGET), kindle-legacy)
  KINDLE_LEGACY_LAUNCHER = launchpad
endif

define UPDATE_PATH_EXCLUDES +=
tools
endef

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# Kindle launching scripts
	$(SYMLINK) $(KINDLE_DIR)/extensions $(INSTALL_DIR)/
	$(SYMLINK) $(KINDLE_DIR)/launchpad $(INSTALL_DIR)/
	$(SYMLINK) $(KINDLE_DIR)/koreader.sh $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(KINDLE_DIR)/libkohelper.sh $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(KINDLE_DIR)/libkohelper.sh $(INSTALL_DIR)/extensions/koreader/bin/
	$(SYMLINK) $(KINDLE_DIR)/wmctrl $(INSTALL_DIR)/koreader/
	# Create packages.
	$(strip $(call mkupdate,$(KINDLE_PACKAGE))) extensions $(KINDLE_LEGACY_LAUNCHER)
	$(strip $(call mkupdate,$(KINDLE_PACKAGE_OTA))) extensions $(KINDLE_LEGACY_LAUNCHER)
	$(strip $(call mkupdate,$(KINDLE_PACKAGE_OLD_OTA))) extensions $(KINDLE_LEGACY_LAUNCHER)

PHONY += update
