#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR=/mnt/onboard/.kobo/koreader

# update to new version from OTA directory
NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
if [ -f $NEWUPDATE ]; then
    # TODO: any graphic indication for the updating progress?
    cd /mnt/onboard/.kobo && tar xf $NEWUPDATE && mv $NEWUPDATE $INSTALLED
fi

# we're always starting from our working directory
cd $KOREADER_DIR

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# fast and dirty way of check if we are called from nickel
# through fmon, or from another launcher (KSM or advboot)
from_nickel=`pidof nickel | wc -c`

if [ $from_nickel -ne 0 ]; then
    # stop kobo software because is running
    killall nickel hindenburg fmon 2>/dev/null
fi

# fallback for old fmon (and advboot) users
if [ `echo $@ | wc -c` -eq 1 ]; then
    args="/mnt/onboard"
else
    args=$@
fi

./reader.lua $args 2> crash.log

if [ $from_nickel -ne 0 ]; then
    # start kobo software because was running before koreader
    ./nickel.sh
else
    # if we were called from advboot then we must reboot to go to the menu
    if [ -d /mnt/onboard/.kobo/advboot ]; then
        reboot
    fi
fi
