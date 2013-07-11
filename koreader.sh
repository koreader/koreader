#!/bin/sh
export LC_ALL="en_US.UTF-8"

PROC_KEYPAD="/proc/keypad"
PROC_FIVEWAY="/proc/fiveway"
test -e $PROC_KEYPAD && echo unlock > $PROC_KEYPAD
test -e $PROC_FIVEWAY && echo unlock > $PROC_FIVEWAY

# we're always starting from our working directory
cd /mnt/us/koreader/

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# bind-mount system fonts
if ! grep /mnt/us/koreader/fonts/host /proc/mounts; then
	mount -o bind /usr/java/lib/fonts /mnt/us/koreader/fonts/host
fi

# check if we are supposed to shut down the Amazon framework
if test "$1" == "--framework_stop"; then
	shift 1
	/etc/init.d/framework stop
fi

# check if kpvbooklet was launched for more than once, if not we will disable pillow
count=`lipc-get-prop -eiq com.github.koreader.kpvbooklet.timer count`
if [ "$count" == "" -o "$count" == "0" ]; then
    lipc-set-prop com.lab126.pillow disableEnablePillow disable
fi

# stop cvm
#killall -stop cvm

# keep only one instance of reader
killall reader.lua

# finally call reader
./reader.lua "$1" 2> crash.log

# unmount system fonts
if grep /mnt/us/koreader/fonts/host /proc/mounts; then
	umount /mnt/us/koreader/fonts/host
fi

# always try to continue cvm
killall -cont cvm || /etc/init.d/framework start

# display chrome bar
lipc-set-prop com.lab126.pillow disableEnablePillow enable

