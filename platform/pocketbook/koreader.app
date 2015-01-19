#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR=/mnt/ext1/applications/koreader

# update to new version from OTA directory
NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
if [ -f $NEWUPDATE ]; then
    # TODO: any graphic indication for the updating progress?
    cd /mnt/ext1/ && tar xf $NEWUPDATE && mv $NEWUPDATE $INSTALLED
fi

# we're always starting from our working directory
cd $KOREADER_DIR

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

if [ `echo $@ | wc -c` -eq 1 ]; then
    args="/mnt/ext1/"
else
    args="$@"
fi

./reader.lua "$args" 2> crash.log

if pidof reader.lua > /dev/null 2>&1 ; then
	killall -TERM reader.lua
fi

