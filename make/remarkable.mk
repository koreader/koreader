REMARKABLE_DIR = $(PLATFORM_DIR)/remarkable
REMARKABLE_PACKAGE = koreader-remarkable$(KODEDUG_SUFFIX)-$(VERSION).zip
REMARKABLE_PACKAGE_OTA = koreader-remarkable$(KODEDUG_SUFFIX)-$(VERSION).targz

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(REMARKABLE_PACKAGE)
	# Remarkable scripts
	cp $(REMARKABLE_DIR)/* $(INSTALL_DIR)/koreader
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
	        zip -9 -r \
	                ../$(REMARKABLE_PACKAGE) \
	                koreader -x "koreader/resources/fonts/*" \
	                "koreader/resources/icons/src/*" "koreader/spec/*" \
	                $(ZIP_EXCLUDE)
	# generate update package index file
	zipinfo -1 $(REMARKABLE_PACKAGE) > \
	        $(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(REMARKABLE_PACKAGE) \
	        koreader/ota/package.index
	# make gzip remarkable update for zsync OTA update
	cd $(INSTALL_DIR) && \
	        tar -I"gzip --rsyncable" -cah --no-recursion -f ../$(REMARKABLE_PACKAGE_OTA) \
	        -T koreader/ota/package.index

PHONY += update
