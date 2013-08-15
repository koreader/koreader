# koreader-base directory
KOR_BASE=koreader-base

# the repository might not have been checked out yet, so make this
# able to fail:
-include $(KOR_BASE)/Makefile.defs

# we want VERSION to carry the version of koreader, not koreader-base
VERSION=$(shell git describe HEAD)

# subdirectory we use to build the installation bundle
INSTALL_DIR=koreader
INSTALL_DIR_KOBO=mnt/onboard/.kobo

# files to link from main directory
INSTALL_FILES=reader.lua frontend resources koreader.sh \
		koreader_kobo.sh defaults.lua \
		git-rev README.md COPYING

# for gettext
DOMAIN=koreader
TEMPLATE_DIR=l10n/templates
KOREADER_MISC_TOOL=../misc
XGETTEXT_BIN=$(KOREADER_MISC_TOOL)/gettext/lua_xgettext.py
MO_DIR=$(INSTALL_DIR)/koreader/i18n


all: mo $(KOR_BASE)/$(OUTPUT_DIR)/luajit
	echo $(VERSION) > git-rev
	mkdir -p $(INSTALL_DIR)/koreader
	cp -rfL $(KOR_BASE)/$(OUTPUT_DIR)/* $(INSTALL_DIR)/koreader/
ifdef EMULATE_READER
	cp -f $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/koreader/
endif
	for f in $(INSTALL_FILES); do \
		ln -sf ../../$$f $(INSTALL_DIR)/koreader/; \
		done
	cp -rpL resources/fonts/* $(INSTALL_DIR)/koreader/fonts/
	mkdir -p $(INSTALL_DIR)/koreader/screenshots
	mkdir -p $(INSTALL_DIR)/koreader/data/dict
	mkdir -p $(INSTALL_DIR)/koreader/data/tessdata
	mkdir -p $(INSTALL_DIR)/koreader/fonts/host
	ln -sf ../extensions $(INSTALL_DIR)/
	ln -sf ../launchpad $(INSTALL_DIR)/
	# clean up
	rm -rf $(INSTALL_DIR)/koreader/data/{cr3.ini,cr3skin-format.txt,desktop,devices,manual}
	rm $(INSTALL_DIR)/koreader/fonts/droid/DroidSansFallbackFull.ttf

$(KOR_BASE)/$(OUTPUT_DIR)/luajit: koreader-base
$(KOR_BASE)/$(OUTPUT_DIR)/extr: koreader-base

koreader-base:
	$(MAKE) -C $(KOR_BASE)

fetchthirdparty:
	git submodule init
	git submodule update
	$(MAKE) -C $(KOR_BASE) fetchthirdparty

clean:
	rm -rf $(INSTALL_DIR)
	$(MAKE) -C $(KOR_BASE) clean

customupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-$(MACHINE)-$(VERSION).zip
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-$(MACHINE)-$(VERSION).zip * \
			-x "koreader/resources/fonts/*"
	# @TODO write an installation script for KUAL   (houqp)

koboupdate: all
	# ensure that the binaries were built for ARM
	file $(KOR_BASE)/koreader-base | grep ARM || exit 1
	file $(KOR_BASE)/extr | grep ARM || exit 1
	# remove old package and dir if any
	rm -f koreader-kobo-$(VERSION).zip
	rm -rf $(INSTALL_DIR)
	# create new dir for package
	mkdir -p $(INSTALL_DIR)/{history,screenshots,clipboard,libs}
	cp -p README.md COPYING $(KOR_BASE)/{koreader-base,extr,sdcv} koreader.sh koreader_kobo.sh $(LUA_FILES) $(INSTALL_DIR)
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/koreader-base $(INSTALL_DIR)/extr $(INSTALL_DIR)/sdcv
	mkdir $(INSTALL_DIR)/data $(INSTALL_DIR)/data/dict $(INSTALL_DIR)/data/tessdata
	cp -L koreader-base/$(DJVULIB) $(KOR_BASE)/$(CRELIB) \
		$(KOR_BASE)/$(LUALIB) $(KOR_BASE)/$(K2PDFOPTLIB) \
		$(KOR_BASE)/$(LEPTONICALIB) $(KOR_BASE)/$(TESSERACTLIB) \
		$(INSTALL_DIR)/libs
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/libs/*
	cp -rpL $(KOR_BASE)/data/*.css $(INSTALL_DIR)/data
	cp -rpL $(KOR_BASE)/data/hyph $(INSTALL_DIR)/data/hyph
	cp -rpL $(KOR_BASE)/fonts $(INSTALL_DIR)
	cp -rp $(MO_DIR) $(INSTALL_DIR)
	rm $(INSTALL_DIR)/fonts/droid/DroidSansFallbackFull.ttf
	echo $(VERSION) > git-rev
	cp -r git-rev resources $(INSTALL_DIR)
	rm -r $(INSTALL_DIR)/resources/fonts
	cp -rpL frontend $(INSTALL_DIR)
	cp defaults.lua $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/fonts/host
	mkdir -p $(INSTALL_DIR_KOBO)/fmon
	cp -rpL fmon $(INSTALL_DIR_KOBO)
	cp -p resources/koreader.png $(INSTALL_DIR_KOBO)/..
	tar -zcvf KoboRoot.tgz mnt/
	zip -9 -r koreader-kobo-$(VERSION).zip $(INSTALL_DIR) KoboRoot.tgz
	rm KoboRoot.tgz
	rm -rf mnt/
	rm -rf $(INSTALL_DIR)

pot:
	$(XGETTEXT_BIN) reader.lua `find frontend -iname "*.lua"` \
		> $(TEMPLATE_DIR)/$(DOMAIN).pot

mo:
	for po in `find l10n -iname '*.po'`; do \
		resource=`basename $$po .po` ; \
		lingua=`dirname $$po | xargs basename` ; \
		mkdir -p $(MO_DIR)/$$lingua/LC_MESSAGES/ ; \
		msgfmt -o $(MO_DIR)/$$lingua/LC_MESSAGES/$$resource.mo $$po ; \
		done

