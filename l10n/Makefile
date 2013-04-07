all: update

update:
	tx pull -a

bootstrap:
	tx set --auto-local -r koreader.koreader "<lang>/koreader.po" \
		--source-language=en \
		--source-file "templates/koreader.pot" --execute

.PHONY: all clean

