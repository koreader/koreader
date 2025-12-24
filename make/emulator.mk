# Run. {{{

PHONY += run run-prompt run-wbuilder

define run_script
	for a in $(RARGS); do \
		[[ "$$a" = [-/]* ]] || a="$${PWD}/$$a"; \
		set -- "$$@" "$$a"; \
	done; \
	cp platform/linux/koreader-emulator.sh $(INSTALL_DIR)/koreader/koreader_emulator.sh && \
	chmod +x $(INSTALL_DIR)/koreader/koreader_emulator.sh && \
	cd $(INSTALL_DIR)/koreader && \
	$(RWRAP) ./koreader_emulator.sh "$$@"
endef

run: all
	$(strip $(run_script))

run-prompt: all
	cd $(INSTALL_DIR)/koreader && $(RWRAP) ./luajit -i setupkoenv.lua

run-wbuilder: all
	cd $(INSTALL_DIR)/koreader && EMULATE_READER_W=540 EMULATE_READER_H=720 $(RWRAP) ./luajit tools/wbuilder.lua

# }}}

# Testing & coverage. {{{

PHONY += coverage coverage-full coverage-run coverage-summary test test%

$(addprefix test,all base bench front): all test-data
	$(RUNTESTS) $(INSTALL_DIR)/koreader $(@:test%=%) $T

test: testall

COVERAGE_STATS = luacov.stats.out
COVERAGE_REPORT = luacov.report.out

$(INSTALL_DIR)/koreader/.luacov:
	$(SYMLINK) .luacov $@

coverage: coverage-summary

coverage-run: all test-data $(INSTALL_DIR)/koreader/.luacov
	rm -f $(addprefix $(INSTALL_DIR)/koreader/,$(COVERAGE_STATS) $(COVERAGE_REPORT))
	# Run tests.
	$(RUNTESTS) $(INSTALL_DIR)/koreader front --coverage $T
	# Aggregate statistics.
	cd $(INSTALL_DIR)/koreader && \
	    eval "$$($(LUAROCKS_BINARY) path)" && \
	    test -r $(COVERAGE_STATS) || \
	    ./luajit tools/merge_luacov_stats.lua $(COVERAGE_STATS) spec/run/*/$(COVERAGE_STATS)
	# Generate report.
	cd $(INSTALL_DIR)/koreader && \
	    eval "$$($(LUAROCKS_BINARY) path)" && \
	    ./luajit -e 'r = require "luacov.runner"; r.run_report(r.configuration)' /dev/null

coverage-full: coverage-run
	cd $(INSTALL_DIR)/koreader && cat luacov.report.out

coverage-summary: coverage-run
	cd $(INSTALL_DIR)/koreader && tail -n \
		+$$(($$(grep -nm1 -e "^Summary$$" luacov.report.out|cut -d: -f1)-1)) \
		luacov.report.out

# }}}

# vim: foldmethod=marker foldlevel=0
