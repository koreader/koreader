MACOS_DIR = $(PLATFORM_DIR)/mac

update: all
	mkdir -p \
		$(INSTALL_DIR)/bundle/Contents/MacOS \
		$(INSTALL_DIR)/bundle/Contents/Resources
	cp -pv $(MACOS_DIR)/koreader.icns $(INSTALL_DIR)/bundle/Contents/Resources/icon.icns
	cp -LR $(INSTALL_DIR)/koreader $(INSTALL_DIR)/bundle/Contents
	cp -pRv $(MACOS_DIR)/menu.xml $(INSTALL_DIR)/bundle/Contents/MainMenu.xib
	ibtool --compile "$(INSTALL_DIR)/bundle/Contents/Resources/Base.lproj/MainMenu.nib" "$(INSTALL_DIR)/bundle/Contents/MainMenu.xib"
	rm -rfv "$(INSTALL_DIR)/bundle/Contents/MainMenu.xib"
	$(CURDIR)/platform/mac/do_mac_bundle.sh $(INSTALL_DIR)

PHONY += update
