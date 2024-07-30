CERVANTES_DIR = $(PLATFORM_DIR)/cervantes
CERVANTES_PACKAGE = koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).zip
CERVANTES_PACKAGE_OTA = koreader-cervantes$(KODEDUG_SUFFIX)-$(VERSION).targz

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(CERVANTES_PACKAGE)
	# Cervantes launching scripts
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader/spinning_zsync.sh
	cp $(CERVANTES_DIR)/*.sh $(INSTALL_DIR)/koreader
	cp $(CERVANTES_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../$(CERVANTES_PACKAGE) \
			koreader -x "koreader/resources/fonts/*" \
			"koreader/resources/icons/src/*" "koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate update package index file
	zipinfo -1 $(CERVANTES_PACKAGE) > \
		$(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(CERVANTES_PACKAGE) \
	koreader/ota/package.index
	# make gzip cervantes update for zsync OTA update
	cd $(INSTALL_DIR) && \
	tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../$(CERVANTES_PACKAGE_OTA) \
	-T koreader/ota/package.index

PHONY += update
