VERSION?=$(shell git describe HEAD)
CHOST?=arm-none-linux-gnueabi
STRIP:=$(CHOST)-strip

all: koreader-base/koreader-base koreader-base/extr

koreader-base/koreader-base:
	cd koreader-base && make koreader-base

koreader-base/extr:
	cd koreader-base && make extr

fetchthirdparty:
	git submodule init
	git submodule update
	cd koreader-base && make fetchthirdparty

clean:
	cd koreader-base && make clean

cleanthirdparty:
	cd koreader-base && make cleanthirdparty

customupdate: all
	# ensure that the binaries were built for ARM
	file koreader-base/koreader-base | grep ARM || exit 1
	file koreader-base/extr | grep ARM || exit 1
	rm -f kindlepdfviewer-$(VERSION).zip
	$(STRIP) --strip-unneeded koreader-base/kpdfview koreader-base/extr
	rm -rf $(INSTALL_DIR)
	mkdir -p $(INSTALL_DIR)/{history,screenshots,clipboard,libs}
	cp -p README.md COPYING kpdfview extr kpdf.sh $(LUA_FILES) $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/data
	cp -L $(DJVULIB) $(CRELIB) $(LUALIB) $(K2PDFOPTLIB) $(INSTALL_DIR)/libs
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/libs/*
	cp -rpL data/*.css $(INSTALL_DIR)/data
	cp -rpL fonts $(INSTALL_DIR)
	rm $(INSTALL_DIR)/fonts/droid/DroidSansFallbackFull.ttf
	cp -r git-rev resources $(INSTALL_DIR)
	cp -rpL frontend $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/fonts/host
	zip -9 -r kindlepdfviewer-$(VERSION).zip $(INSTALL_DIR) launchpad/ extensions/
	rm -rf $(INSTALL_DIR)
	@echo "copy kindlepdfviewer-$(VERSION).zip to /mnt/us/customupdates and install with shift+shift+I"
