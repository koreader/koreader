KINDLE_DIR = $(PLATFORM_DIR)/kindle
KINDLE_PACKAGE = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip
KINDLE_PACKAGE_OTA = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).targz
ZIP_EXCLUDE = -x "*.swp" -x "*.swo" -x "*.orig" -x "*.un~"

# Don't bundle launchpad on touch devices..
ifeq ($(TARGET), kindle-legacy)
  KINDLE_LEGACY_LAUNCHER = launchpad
endif

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(KINDLE_PACKAGE)
	# Kindle launching scripts
	$(SYMLINK) $(KINDLE_DIR)/extensions $(INSTALL_DIR)/
	$(SYMLINK) $(KINDLE_DIR)/launchpad $(INSTALL_DIR)/
	$(SYMLINK) $(KINDLE_DIR)/koreader.sh $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(KINDLE_DIR)/libkohelper.sh $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(KINDLE_DIR)/libkohelper.sh $(INSTALL_DIR)/extensions/koreader/bin/
	$(SYMLINK) $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader/
	$(SYMLINK) $(KINDLE_DIR)/wmctrl $(INSTALL_DIR)/koreader/
	# create new package
	cd $(INSTALL_DIR) && pwd && \
		zip -9 -r \
			../$(KINDLE_PACKAGE) \
			extensions koreader $(KINDLE_LEGACY_LAUNCHER) \
			-x "koreader/resources/fonts/*" "koreader/ota/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate kindleupdate package index file
	zipinfo -1 $(KINDLE_PACKAGE) > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(KINDLE_PACKAGE) \
		koreader/ota/package.index
	# make gzip kindleupdate for zsync OTA update
	# note that the targz file extension is intended to keep ISP from caching
	# the file, see koreader#1644.
	cd $(INSTALL_DIR) && \
		tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../$(KINDLE_PACKAGE_OTA) \
		-T koreader/ota/package.index

PHONY += update
