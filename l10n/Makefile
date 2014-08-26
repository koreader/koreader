all: bootstrap push pull

bootstrap:
	tx set --auto-local -r koreader.koreader "<lang>/koreader.po" \
		--source-language=en \
		--source-file "templates/koreader.pot" --execute

pull:
	tx pull -a -f

push:
	tx push -sl en

.PHONY: all clean

