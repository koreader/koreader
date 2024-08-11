# Run. {{{

PHONY += run run-prompt run-wbuilder

define run_script
for a in $(RARGS); do
    [[ "$$a" = [-/]* ]] || a="$${PWD}/$$a";
    set -- "$$@" "$$a";
done;
cd $(INSTALL_DIR)/koreader &&
while true; do
    code=0;
    $(RWRAP) ./luajit reader.lua "$$@" || code=$$?;
    [ $${code} -eq 85 ] || exit $${code};
    set --;
done
endef

run: all
	$(strip $(run_script))

run-prompt: all
	cd $(INSTALL_DIR)/koreader && ./luajit -i setupkoenv.lua

run-wbuilder: all
	cd $(INSTALL_DIR)/koreader && EMULATE_READER_W=540 EMULATE_READER_H=720 ./luajit tools/wbuilder.lua

# }}}

# Testing & coverage. {{{

PHONY += coverage test testbase testfront

$(INSTALL_DIR)/koreader/.busted: .busted
	$(SYMLINK) .busted $@

$(INSTALL_DIR)/koreader/.luacov:
	$(SYMLINK) .luacov $@

testbase: base-test

testfront: all test-data $(INSTALL_DIR)/koreader/.busted
	# sdr files may have unexpected impact on unit testing
	-rm -rf spec/unit/data/*.sdr
	cd $(INSTALL_DIR)/koreader && $(BUSTED_LUAJIT) $(BUSTED_OVERRIDES) $(BUSTED_SPEC_FILE)

test: testbase testfront

coverage: $(INSTALL_DIR)/koreader/.luacov
	-rm -rf $(INSTALL_DIR)/koreader/luacov.*.out
	cd $(INSTALL_DIR)/koreader && \
		./luajit $(shell which busted) --output=gtest \
			--sort-files \
			--coverage --exclude-tags=nocov
	# coverage report summary
	cd $(INSTALL_DIR)/koreader && tail -n \
		+$$(($$(grep -nm1 -e "^Summary$$" luacov.report.out|cut -d: -f1)-1)) \
		luacov.report.out

# }}}

# vim: foldmethod=marker foldlevel=0
