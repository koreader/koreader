KOBO_DIR = $(PLATFORM_DIR)/kobo
KOBO_PACKAGE = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).zip
KOBO_PACKAGE_OTA = koreader-$(DIST)$(KODEDUG_SUFFIX)-$(VERSION).targz

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(KOBO_PACKAGE)
	# Kobo launching scripts
	cp $(KOBO_DIR)/koreader.png $(INSTALL_DIR)/koreader.png
	cp $(KOBO_DIR)/*.sh $(INSTALL_DIR)/koreader
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../$(KOBO_PACKAGE) \
			koreader -x "koreader/resources/fonts/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate koboupdate package index file
	zipinfo -1 $(KOBO_PACKAGE) > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(KOBO_PACKAGE) \
		koreader/ota/package.index koreader.png README_kobo.txt
	# make gzip koboupdate for zsync OTA update
	cd $(INSTALL_DIR) && \
		tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../$(KOBO_PACKAGE_OTA) \
		-T koreader/ota/package.index

PHONY += update
