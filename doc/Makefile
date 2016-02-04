all:
ifeq (,$(shell which ldoc))
	$(error ldoc not found, please install via luarocks.)
endif
	ldoc .

clean:
	rm -rf html
