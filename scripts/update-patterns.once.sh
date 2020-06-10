#!/system/bin/sh

# $1 is the koreader user directory
# $2 is the koreader system directory

SYSTEM_DIR=$2

# copy pattern files from user to system directory
if  [ -d $1/hyph ]; then
	for i in $(ls $1/hyph/*.pattern); do
		cp $i $SYSTEM_DIR/data/hyph/
	done
fi

