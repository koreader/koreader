#!/system/bin/sh

# $1 is the koreader user directory
# $2 is the koreader system directory

HYPH_DIR=$2/data/hyph/

#copy newer patterns fomr user to system directory
if [ -d "$1"/hyph ]; then
	cd "$1"/hyph/ || exit
	for i in $(ls *.pattern); do
		[ ! -f "$i" ] && cp "$i" "$HYPHT_DIR"
		[ "$i" -nt "$HYPH_DIR"/"$i" ] && cp "$i" "$HYPH_DIR"/
	done
fi

