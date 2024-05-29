LINUX_DIR = $(PLATFORM_DIR)/linux
LINUX_PACKAGE:=koreader-linux-$(LINUX_ARCH_NAME)$(KODEDUG_SUFFIX)-$(VERSION).tar.xz

GLIBC_VERSION := $(shell ldd --version | sed -n '1s/.* \([0-9.]\+\)$$/\1/p')

update: all
	mkdir -pv \
		$(INSTALL_DIR)/linux/bin \
		$(INSTALL_DIR)/linux/lib \
		$(INSTALL_DIR)/linux/share/pixmaps \
		$(INSTALL_DIR)/linux/share/metainfo \
		$(INSTALL_DIR)/linux/share/applications \
		$(INSTALL_DIR)/linux/share/doc/koreader \
		$(INSTALL_DIR)/linux/share/man/man1
	sed -e 's/%%VERSION%%/$(VERSION)/g' -e 's/%%DATE%%/$(RELEASE_DATE)/' $(PLATFORM_DIR)/common/koreader.metainfo.xml >$(INSTALL_DIR)/linux/share/metainfo/koreader.metainfo.xml
	cp -pv resources/koreader.png $(INSTALL_DIR)/linux/share/pixmaps
	cp -pv $(LINUX_DIR)/koreader.desktop $(INSTALL_DIR)/linux/share/applications
	cp -pv $(LINUX_DIR)/copyright COPYING $(INSTALL_DIR)/linux/share/doc/koreader
	cp -pv $(LINUX_DIR)/koreader.sh $(INSTALL_DIR)/linux/bin/koreader
	cp -Lr $(INSTALL_DIR)/koreader $(INSTALL_DIR)/linux/lib
	gzip -cn9 $(LINUX_DIR)/koreader.1 > $(INSTALL_DIR)/linux/share/man/man1/koreader.1.gz
	chmod 644 \
		$(INSTALL_DIR)/linux/share/doc/koreader/copyright \
		$(INSTALL_DIR)/linux/share/man/man1/koreader.1.gz
	rm -rf \
		$(INSTALL_DIR)/linux/lib/koreader/{ota,cache,clipboard,screenshots,spec,tools,resources/fonts,resources/icons/src}

	# remove leftovers
	find $(INSTALL_DIR)/linux -type f \( -name ".git" -o -name ".gitignore" -o -name "discovery2spore" -o -name "wadl2spore" -o -name "*.txt" -o -name "LICENSE*" -o -name "NOTICE" -o -name "README.md" \) -print0 | xargs -0 rm -rf
	find $(INSTALL_DIR)/linux -type d \( -name "test" -o -name ".github" \) -print0 | xargs -0 rm -rf

	# add instructions
	sed -e 's/%%VERSION%%/$(VERSION)/' \
		-e 's/%%ARCH%%/$(LINUX_ARCH_NAME)/' \
		-e 's/%%ABI%%/$(GLIBC_VERSION)/' \
		 $(LINUX_DIR)/instructions.txt >$(INSTALL_DIR)/linux/README.md

	# fix permissions
	chmod -R u=rwX,og=rX $(INSTALL_DIR)/linux
	XZ_OPT=9 tar -C $(INSTALL_DIR)/linux -cvJf $(LINUX_PACKAGE) .

	rm -rf $(INSTALL_DIR)/linux

PHONY += update
