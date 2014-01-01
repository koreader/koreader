# koreader-base directory
KOR_BASE?=koreader-base

# the repository might not have been checked out yet, so make this
# able to fail:
-include $(KOR_BASE)/Makefile.defs

# we want VERSION to carry the version of koreader, not koreader-base
VERSION=$(shell git describe HEAD)

# subdirectory we use to build the installation bundle
INSTALL_DIR=koreader-$(MACHINE)

# files to link from main directory
INSTALL_FILES=reader.lua frontend resources koreader.sh \
		koreader_kobo.sh kobo_suspend.sh defaults.lua \
		git-rev README.md COPYING

# for gettext
DOMAIN=koreader
TEMPLATE_DIR=l10n/templates
KOREADER_MISC_TOOL=../misc
XGETTEXT_BIN=$(KOREADER_MISC_TOOL)/gettext/lua_xgettext.py
MO_DIR=$(INSTALL_DIR)/koreader/i18n


all: $(KOR_BASE)/$(OUTPUT_DIR)/luajit po mo
	$(MAKE) -C $(KOR_BASE)
	echo $(VERSION) > git-rev
	mkdir -p $(INSTALL_DIR)/koreader
ifdef EMULATE_READER
	cp -f $(KOR_BASE)/ev_replay.py $(INSTALL_DIR)/koreader/
	# create symlink instead of copying files in development mode
	cd $(INSTALL_DIR)/koreader && \
		ln -sf ../../$(KOR_BASE)/$(OUTPUT_DIR)/* .
else
	cp -rfL $(KOR_BASE)/$(OUTPUT_DIR)/* $(INSTALL_DIR)/koreader/
endif
	for f in $(INSTALL_FILES); do \
		ln -sf ../../$$f $(INSTALL_DIR)/koreader/; \
	done
	cp -rpL resources/fonts/* $(INSTALL_DIR)/koreader/fonts/
	mkdir -p $(INSTALL_DIR)/koreader/screenshots
	mkdir -p $(INSTALL_DIR)/koreader/data/dict
	mkdir -p $(INSTALL_DIR)/koreader/data/tessdata
	mkdir -p $(INSTALL_DIR)/koreader/fonts/host
	# Kindle startup
	ln -sf ../extensions $(INSTALL_DIR)/
	ln -sf ../launchpad $(INSTALL_DIR)/
	# Kobo startup
	mkdir -p $(INSTALL_DIR)/kobo/mnt/onboard/.kobo
	ln -sf ../../../../../fmon $(INSTALL_DIR)/kobo/mnt/onboard/.kobo/
	cd $(INSTALL_DIR)/kobo && tar -czhf ../KoboRoot.tgz mnt
	cp resources/koreader.png $(INSTALL_DIR)/koreader.png
	cp fmon/README.txt $(INSTALL_DIR)/README_kobo.txt
ifndef EMULATE_READER
	# clean up, remove unused files for releases
	rm -rf $(INSTALL_DIR)/koreader/data/{cr3.ini,cr3skin-format.txt,desktop,devices,manual}
	rm $(INSTALL_DIR)/koreader/fonts/droid/DroidSansFallbackFull.ttf
endif

$(KOR_BASE)/$(OUTPUT_DIR)/luajit:
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
	rm -f koreader-kindle-$(MACHINE)-$(VERSION).zip
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-kindle-$(MACHINE)-$(VERSION).zip \
			extensions koreader launchpad \
			-x "koreader/resources/fonts/*"
	# @TODO write an installation script for KUAL   (houqp)

koboupdate: all
	# ensure that the binaries were built for ARM
	file $(INSTALL_DIR)/koreader/luajit | grep ARM || exit 1
	# remove old package if any
	rm -f koreader-kobo-$(MACHINE)-$(VERSION).zip
	# create new package
	cd $(INSTALL_DIR) && \
		zip -9 -r \
			../koreader-kobo-$(MACHINE)-$(VERSION).zip \
			KoboRoot.tgz koreader koreader.png README_kobo.txt \
			-x "koreader/resources/fonts/*"

pot:
	$(XGETTEXT_BIN) reader.lua `find frontend -iname "*.lua"` \
		> $(TEMPLATE_DIR)/$(DOMAIN).pot

po:
	$(MAKE) -i -C l10n bootstrap update

mo:
	for po in `find l10n -iname '*.po'`; do \
		resource=`basename $$po .po` ; \
		lingua=`dirname $$po | xargs basename` ; \
		mkdir -p $(MO_DIR)/$$lingua/LC_MESSAGES/ ; \
		msgfmt -o $(MO_DIR)/$$lingua/LC_MESSAGES/$$resource.mo $$po ; \
		done

