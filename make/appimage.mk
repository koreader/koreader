APPDIR = $(INSTALL_DIR)/AppDir
APPIMAGE_DIR = $(PLATFORM_DIR)/appimage

UBUNTU_LIBBSD = /lib/$(TARGET_MACHINE)/libbsd.so.0

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autofrontlight.koplugin
plugins/timesync.koplugin
$(filter-out tools/trace_require.lua tools/wbuilder.lua,$(wildcard tools/*))
endef

update-appimage: all $(MKAPPIMAGE)
	$(call mkupdate_linux,$(APPDIR))
	# Setup AppDir.
	ln -s usr/bin/koreader $(APPDIR)/AppRun
	ln -s usr/share/applications/$(DIST_APPID).desktop $(APPDIR)/
ifeq (,$(wildcard $(UBUNTU_LIBBSD)))
	# Only warn if it's missing (e.g. when testing on a non-Ubuntu distribution).
	echo 'WARNING: not bundling missing $(UBUNTU_LIBBSD)' 1>&2
else
	install $(UBUNTU_LIBBSD) -t $(APPDIR)/usr/lib/koreader/libs/
endif
	# Generate AppImage.
	echo 'Creating appimage: $(LINUX_PACKAGE)'
	$(call appimage_generate,koreader,$(VERSION))
	# Cleanup.
	rm -rf $(APPDIR)

update: update-appimage
