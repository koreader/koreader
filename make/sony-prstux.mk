SONY_PRSTUX_DIR = $(PLATFORM_DIR)/sony-prstux
SONY_PRSTUX_PACKAGE = koreader-sony-prstux$(KODEDUG_SUFFIX)-$(VERSION).zip
SONY_PRSTUX_PACKAGE_OTA = koreader-sony-prstux$(KODEDUG_SUFFIX)-$(VERSION).targz

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(SONY_PRSTUX_PACKAGE)
	# Sony PRSTUX launching scripts
	cp $(SONY_PRSTUX_DIR)/*.sh $(INSTALL_DIR)/koreader
	# create new package
	cd $(INSTALL_DIR) && \
	        zip -9 -r \
	                ../$(SONY_PRSTUX_PACKAGE) \
	                koreader -x "koreader/resources/fonts/*" \
	                "koreader/resources/icons/src/*" "koreader/spec/*" \
	                $(ZIP_EXCLUDE)
	# generate update package index file
	zipinfo -1 $(SONY_PRSTUX_PACKAGE) > \
	        $(INSTALL_DIR)/koreader/ota/package.index
	echo "koreader/ota/package.index" >> $(INSTALL_DIR)/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -u ../$(SONY_PRSTUX_PACKAGE) \
	        koreader/ota/package.index
	# make gzip sonyprstux update for zsync OTA update
	cd $(INSTALL_DIR) && \
	        tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../$(SONY_PRSTUX_PACKAGE_OTA) \
	        -T koreader/ota/package.index

PHONY += update
