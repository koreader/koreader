all:
ifeq (,$(shell which ldoc))
	$(error ldoc not found, please install via luarocks.)
endif
	mkdir generated -p
	touch generated/Events_and_handler.md

	ln -s -t ../frontend/ ../plugins
	ldoc .
	rm ../frontend/plugins

events:
ifeq (,$(shell which ldoc))
	$(error ldoc not found, please install via luarocks.)
endif
	rm -f no_stash.tmp
	git stash && touch no_stash.tmp

	mkdir generated -p
	touch generated/Events_and_handler.md

	# Add a symbolic link to plugins in frontend,
	# otherwise ldoc does not get a module name.
	ln -s -t ../frontend/ ../plugins || true

	# It is enough to scan frontend, as we have the link to plugins there.
	events_helper/document_events.sh 2 ../frontend

	# Write event/handler documentation to generated/Events_and_handler.md
	ldoc --filter events.filter .
	ldoc .

	# Remove the link again
	rm ../frontend/plugins

	# Remove all changes done by annotation
	git stash && git stash drop || true

	[[ -f no_stash.tmp ]] || git stash pop
	rm no_stash.tmp
test:
	ldoc --all .

clean:
	rm -rf html
