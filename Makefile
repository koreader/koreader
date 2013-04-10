# koreader-base directory
KOR_BASE=koreader-base

# the repository might not have been checked out yet, so make this
# able to fail:
-include $(KOR_BASE)/Makefile.defs

# we want VERSION to carry the version of koreader, not koreader-base
VERSION=$(shell git describe HEAD)

# subdirectory we use to build the installation bundle
INSTALL_DIR=koreader

# subdirectory we use to setup emulation environment
EMU_DIR=emu

# files to copy from main directory
LUA_FILES=reader.lua

# for gettext
DOMAIN=koreader
TEMPLATE_DIR=l10n/templates
KOREADER_MISC_TOOL=../misc
XGETTEXT_BIN=$(KOREADER_MISC_TOOL)/gettext/lua_xgettext.py
MO_DIR=i18n


all: $(KOR_BASE)/koreader-base $(KOR_BASE)/extr mo

$(KOR_BASE)/koreader-base $(KOR_BASE)/extr:
	make -C $(KOR_BASE) koreader-base extr

fetchthirdparty:
	git submodule init
	git submodule update
	make -C $(KOR_BASE) fetchthirdparty

clean:
	make -C $(KOR_BASE) clean

cleanthirdparty:
	make -C $(KOR_BASE) cleanthirdparty

bootstrapemu:
	test -d $(EMU_DIR) || mkdir $(EMU_DIR)
	test -d $(EMU_DIR)/libs-emu || (cd $(EMU_DIR) && ln -s ../$(KOR_BASE)/libs-emu ./)
	test -d $(EMU_DIR)/fonts || (cd $(EMU_DIR) && ln -s ../$(KOR_BASE)/fonts ./)
	test -d $(EMU_DIR)/data || (cd $(EMU_DIR) && ln -s ../$(KOR_BASE)/data ./)
	test -d $(EMU_DIR)/frontend || (cd $(EMU_DIR) && ln -s ../frontend ./)
	test -d $(EMU_DIR)/resources || (cd $(EMU_DIR) && ln -s ../resources ./)
	test -e $(EMU_DIR)/koreader-base || (cd $(EMU_DIR) && ln -s ../$(KOR_BASE)/koreader-base ./)
	test -e $(EMU_DIR)/extr || (cd $(EMU_DIR) && ln -s ../$(KOR_BASE)/extr ./)
	test -e $(EMU_DIR)/reader.lua || (cd $(EMU_DIR) && ln -s ../reader.lua ./)
	test -e $(EMU_DIR)/history || (mkdir $(EMU_DIR)/history)
	test -e $(EMU_DIR)/$(MO_DIR) || (cd $(EMU_DIR) && ln -s ../$(MO_DIR) ./)

customupdate: all
	# ensure that the binaries were built for ARM
	file $(KOR_BASE)/koreader-base | grep ARM || exit 1
	file $(KOR_BASE)/extr | grep ARM || exit 1
	# remove old package and dir if any
	rm -f koreader-$(VERSION).zip
	rm -rf $(INSTALL_DIR)
	# create new dir for package
	mkdir -p $(INSTALL_DIR)/{history,screenshots,clipboard,libs}
	cp -p README.md COPYING $(KOR_BASE)/{koreader-base,extr} koreader.sh $(LUA_FILES) $(INSTALL_DIR)
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/koreader-base $(INSTALL_DIR)/extr
	mkdir $(INSTALL_DIR)/data
	cp -L koreader-base/$(DJVULIB) $(KOR_BASE)/$(CRELIB) $(KOR_BASE)/$(LUALIB) $(KOR_BASE)/$(K2PDFOPTLIB) $(INSTALL_DIR)/libs
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/libs/*
	cp -rpL $(KOR_BASE)/data/*.css $(INSTALL_DIR)/data
	cp -rpL $(KOR_BASE)/fonts $(INSTALL_DIR)
	cp -rp $(MO_DIR) $(INSTALL_DIR)
	rm $(INSTALL_DIR)/fonts/droid/DroidSansFallbackFull.ttf
	echo $(VERSION) > git-rev
	cp -r git-rev resources $(INSTALL_DIR)
	cp -rpL frontend $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/fonts/host
	zip -9 -r koreader-$(VERSION).zip $(INSTALL_DIR) launchpad/ extensions/
	rm -rf $(INSTALL_DIR)
	# @TODO write an installation script for KUAL   (houqp)


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


