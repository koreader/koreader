#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR=/mnt/onboard/.kobo/koreader

# update to new version from OTA directory
NEWUPDATE=${KOREADER_DIR}/ota/koreader.updated.tar
if [ -f $NEWUPDATE ]; then
    # TODO: any graphic indication for the updating progress?
    cd /mnt/onboard/.kobo && tar xf $NEWUPDATE && rm $NEWUPDATE
fi

# we're always starting from our working directory
cd $KOREADER_DIR

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# exit from nickel
killall nickel hindenburg fmon

# finally call the launcher
./reader.lua /mnt/onboard 2> crash.log

# back to nickel
./nickel.sh
