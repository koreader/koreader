BOOKEEN_DIR = $(PLATFORM_DIR)/bookeen

# $(VERSION) is derived from `git describe` plus the *commit* date, so it is
# byte-identical across rebuilds of the same commit -- which means every package
# overwrote the last one and there was no way to tell two builds apart on the
# device. Stamp the build time into the filename instead.
#
# Deliberately filename-only: $(VERSION) itself is left alone, so the `git-rev`
# written into the package (Makefile `all:`) and the version comparison
# OTAManager does against it are unchanged. `:=` matters here -- with `=` this
# would re-run `date` for each mkupdate call below and could straddle a second
# boundary, naming the packages differently.
BOOKEEN_BUILD_STAMP := $(shell date -u +%Y%m%d-%H%M%S)

BOOKEEN_PACKAGE = koreader-bookeen$(KODEDUG_SUFFIX)-$(VERSION)-$(BOOKEEN_BUILD_STAMP).zip
BOOKEEN_PACKAGE_OTA = koreader-bookeen$(KODEDUG_SUFFIX)-$(VERSION)-$(BOOKEEN_BUILD_STAMP).tar.xz
BOOKEEN_PACKAGE_OLD_OTA = koreader-bookeen$(KODEDUG_SUFFIX)-$(VERSION)-$(BOOKEEN_BUILD_STAMP).targz

define UPDATE_PATH_EXCLUDES +=
tools
endef

update-prepare: all
	# ensure that the binaries were built for ARM
	file --dereference $(INSTALL_DIR)/koreader/luajit | grep ARM
	# Bookeen launching scripts
	$(SYMLINK) $(BOOKEEN_DIR)/* $(INSTALL_DIR)/koreader/

update-zip: update-prepare
	$(strip $(call mkupdate,$(BOOKEEN_PACKAGE)))

update-txz: update-prepare
	$(strip $(call mkupdate,$(BOOKEEN_PACKAGE_OTA)))

update-tgz: update-prepare
	$(strip $(call mkupdate,$(BOOKEEN_PACKAGE_OLD_OTA)))

update: update-zip update-txz update-tgz
