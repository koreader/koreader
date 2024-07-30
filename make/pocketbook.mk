POCKETBOOK_DIR = $(PLATFORM_DIR)/pocketbook
PB_PACKAGE = koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).zip
PB_PACKAGE_OTA = koreader-pocketbook$(KODEDUG_SUFFIX)-$(VERSION).targz

update: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# remove old package if any
	rm -f $(PB_PACKAGE)
	# Pocketbook launching scripts
	mkdir -p $(INSTALL_DIR)/applications
	mkdir -p $(INSTALL_DIR)/system/bin
	cp $(POCKETBOOK_DIR)/koreader.app $(INSTALL_DIR)/applications
	cp $(POCKETBOOK_DIR)/system_koreader.app $(INSTALL_DIR)/system/bin/koreader.app
	cp $(COMMON_DIR)/spinning_zsync $(INSTALL_DIR)/koreader
	cp -rfL $(INSTALL_DIR)/koreader $(INSTALL_DIR)/applications
	find $(INSTALL_DIR)/applications/koreader \
		-type f \( -name "*.gif" -o -name "*.html" -o -name "*.md" -o -name "*.txt" \) \
		-exec rm -vf {} \;
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../$(PB_PACKAGE) \
			applications -x "applications/koreader/resources/fonts/*" \
			"applications/koreader/resources/icons/src/*" "applications/koreader/spec/*" \
			$(ZIP_EXCLUDE)
	# generate pocketbook package index file
	zipinfo -1 $(PB_PACKAGE) > \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	echo "applications/koreader/ota/package.index" >> \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	# hack file path when running tar in parent directory of koreader
	sed -i -e 's/^/..\//' \
		$(INSTALL_DIR)/applications/koreader/ota/package.index
	# update index file in zip package
	cd $(INSTALL_DIR) && zip -ru ../$(PB_PACKAGE) \
		applications/koreader/ota/package.index system
	# make gzip pbupdate for zsync OTA update
	cd $(INSTALL_DIR)/applications && \
		tar --hard-dereference -I"gzip --rsyncable" -cah --no-recursion -f ../../$(PB_PACKAGE_OTA) \
		-T koreader/ota/package.index

PHONY += update
