all:
ifeq (,$(shell which ldoc))
	$(error ldoc not found, please install via luarocks.)
endif
	mkdir generated -p
	touch generated/Events_and_handler.md

	ln -s -t ../frontend/ ../plugins || true
	ldoc .
	rm ../frontend/plugins

events:
ifeq (,$(shell which ldoc))
	$(error ldoc not found, please install via luarocks.)
endif
	rm -f no_stash.tmp

	# Check number of stash entries before and after stash
	git stash list | wc -l > stashes_before.tmp
	git stash
	git stash list | wc -l > stashes_after.tmp

	# create the no_stash.tmp file if no stash has happened
	diff stashes_before.tmp stashes_after.tmp && touch no_stash.tmp || true
	rm stashes_before.tmp stashes_after.tmp

	mkdir generated -p
	touch generated/Events_and_handler.md

	# Add a symbolic link to plugins in frontend,
	# otherwise ldoc does not get a module name.
	ln -s -t ../frontend/ ../plugins || true

	# It is enough to scan frontend, as we have the link to plugins there.
	events_helper/document_events.sh ../frontend

	# Write event/handler documentation to generated/Events_and_handler.md
	ldoc --filter events.filter .
	ldoc .

	# Remove the link again
	rm ../frontend/plugins

	# Remove all changes done by annotation
	git stash && git stash drop || true

	# Redo the initial stash, if necessary
	[ ! -f no_stash.tmp ] && git stash pop || true
	rm -f no_stash.tmp

clean:
	rm -rf html
