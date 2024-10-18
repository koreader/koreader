MACOS_DIR = $(PLATFORM_DIR)/mac

define UPDATE_PATH_EXCLUDES +=
plugins/SSH.koplugin
plugins/autofrontlight.koplugin
plugins/hello.koplugin
plugins/timesync.koplugin
tools
endef

update: all
	mkdir -p $(INSTALL_DIR)/bundle/Contents/{MacOS,Resources}
	cp -pv $(MACOS_DIR)/koreader.icns $(INSTALL_DIR)/bundle/Contents/Resources/icon.icns
	cd $(INSTALL_DIR)/koreader && '$(abspath tools/mkrelease.sh)' ../bundle/Contents/koreader/ . $(release_excludes)
	cp -pv $(MACOS_DIR)/menu.xml $(INSTALL_DIR)/bundle/Contents/MainMenu.xib
	ibtool --compile $(INSTALL_DIR)/bundle/Contents/Resources/Base.lproj/MainMenu.nib $(INSTALL_DIR)/bundle/Contents/MainMenu.xib
	rm -vf $(INSTALL_DIR)/bundle/Contents/MainMenu.xib
	$(CURDIR)/platform/mac/do_mac_bundle.sh $(INSTALL_DIR)

PHONY += update
