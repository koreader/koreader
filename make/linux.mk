LINUX_DIR = $(PLATFORM_DIR)/linux
LINUX_PACKAGE = koreader-linux-$(LINUX_ARCH_NAME)$(KODEDUG_SUFFIX)-$(VERSION).tar.xz
LINUX_PACKAGE_COMPRESSION_LEVEL ?= 9

GLIBC_VERSION = $(shell ldd --version | sed -n '1s/.* \([0-9.]\+\)$$/\1/p')

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autofrontlight.koplugin
plugins/timesync.koplugin
$(filter-out tools/trace_require.lua tools/wbuilder.lua,$(wildcard tools/*))
endef

# Override the default emulator run target to use the shell script
run: prepare
	@echo "[*] Running via koreader.sh..."
	$(INSTALL_DIR)/linux/bin/koreader $(RARGS)

prepare: all
	rm -rf $(INSTALL_DIR)/linux
	mkdir -p $(INSTALL_DIR)/linux/{bin,lib,share/{applications,doc/koreader,man/man1,metainfo,pixmaps}}
	sed -e 's/%%VERSION%%/$(VERSION)/g' -e 's/%%DATE%%/$(RELEASE_DATE)/' $(PLATFORM_DIR)/common/koreader.metainfo.xml >$(INSTALL_DIR)/linux/share/metainfo/koreader.metainfo.xml
	$(SYMLINK) $(LINUX_DIR)/koreader.sh $(INSTALL_DIR)/linux/bin/koreader
	$(SYMLINK) $(INSTALL_DIR)/koreader $(INSTALL_DIR)/linux/lib/
	$(SYMLINK) resources/koreader.png $(INSTALL_DIR)/linux/share/pixmaps/
	$(SYMLINK) $(LINUX_DIR)/koreader.desktop $(INSTALL_DIR)/linux/share/applications/
	$(SYMLINK) $(LINUX_DIR)/copyright COPYING $(INSTALL_DIR)/linux/share/doc/koreader/
	gzip -cn9 $(LINUX_DIR)/koreader.1 >$(INSTALL_DIR)/linux/share/man/man1/koreader.1.gz
	# Add instructions.
	sed -e 's/%%VERSION%%/$(VERSION)/' \
		-e 's/%%ARCH%%/$(LINUX_ARCH_NAME)/' \
		-e 's/%%ABI%%/$(GLIBC_VERSION)/' \
		 $(LINUX_DIR)/instructions.txt >$(INSTALL_DIR)/linux/README.md

update: prepare
	# Create archive.
	cd $(INSTALL_DIR)/linux && \
		'$(abspath tools/mkrelease.sh)' \
		$(if $(PARALLEL_JOBS),--jobs $(PARALLEL_JOBS)) \
		--options=-$(LINUX_PACKAGE_COMPRESSION_LEVEL) \
		'$(abspath $(LINUX_PACKAGE))' . $(call release_excludes,lib/koreader/)

PHONY += update run
