APPIMAGE_ARCH_arm64 = aarch64
APPIMAGE_ARCH = $(or $(APPIMAGE_ARCH_$(LINUX_ARCH)),$(LINUX_ARCH))
APPIMAGE_DIR = $(PLATFORM_DIR)/appimage
APPIMAGE_NAME = koreader-$(VERSION)-$(APPIMAGE_ARCH).AppImage

MKAPPIMAGE = mkappimage-$(APPIMAGE_ARCH).AppImage
define MKAPPIMAGE_URL
$(WGET) -O - https://api.github.com/repos/probonopd/go-appimage/releases | jq -r '.[]
 | select(.tag_name == "continuous")
 | .assets[]
 | select(.name | test("^mkappimage-.*-$(APPIMAGE_ARCH).AppImage$$"))
 | .browser_download_url
'
endef

UBUNTU_LIBBSD = /lib/$(TARGET_MACHINE)/libbsd.so.0

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autofrontlight.koplugin
plugins/timesync.koplugin
$(filter-out tools/trace_require.lua tools/wbuilder.lua,$(wildcard tools/*))
endef

mkappimage $(MKAPPIMAGE):
	$(WGET) -O $(MKAPPIMAGE).part "$$($(strip $(MKAPPIMAGE_URL)))"
	# Zero-out AppImage magic bytes from the ELF header extended ABI version so
	# binfmt+qemu can be used (e.g. when executed from `docker run --platform …`).
	# Cf. https://github.com/AppImage/AppImageKit/issues/1056.
	printf '\0\0\0' | dd conv=notrunc obs=1 seek=8 of=$(MKAPPIMAGE).part
	chmod +x ./$(MKAPPIMAGE).part
	mv $(MKAPPIMAGE).part $(MKAPPIMAGE)

update-appimage: all $(MKAPPIMAGE)
	$(call mkupdate_linux,$(INSTALL_DIR)/appimage)
	# Setup AppDir.
	ln -s usr/bin/koreader $(INSTALL_DIR)/appimage/AppRun
	ln -s usr/share/applications/$(DIST_APPID).desktop $(INSTALL_DIR)/appimage/
ifeq (,$(wildcard $(UBUNTU_LIBBSD)))
	# Only warn if it's missing (e.g. when testing on a non-Ubuntu distribution).
	echo 'WARNING: not bundling missing $(UBUNTU_LIBBSD)' 1>&2
else
	install $(UBUNTU_LIBBSD) -t $(INSTALL_DIR)/appimage/usr/lib/koreader/libs/
endif
	# Generate AppImage.
	echo 'Creating appimage: $(LINUX_PACKAGE)'
	ARCH='$(APPIMAGE_ARCH)' VERSION='$(VERSION)' ./$(MKAPPIMAGE) --appimage-extract-and-run $(INSTALL_DIR)/appimage $(APPIMAGE_NAME)
	# Cleanup.
	rm -rf $(INSTALL_DIR)/appimage

update: update-appimage

PHONY += mkappimage
SOUND += $(MKAPPIMAGE)
