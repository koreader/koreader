#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR=/mnt/ext1/applications/koreader

# update to new version from OTA directory
NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
if [ -f "${NEWUPDATE}" ]; then
    # TODO: any graphic indication for the updating progress?
    cd /mnt/ext1/ && "${KOREADER_DIR}/tar" xf "${NEWUPDATE}" --no-same-permissions --no-same-owner &&
        mv "${NEWUPDATE}" "${INSTALLED}"
    rm -f "${NEWUPDATE}" # always purge newupdate in all cases to prevent update loop
fi

# we're always starting from our working directory
cd ${KOREADER_DIR} || exit

# export load library path for some old firmware
export LD_LIBRARY_PATH=${KOREADER_DIR}/libs:${LD_LIBRARY_PATH}

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# export external font directory
export EXT_FONT_DIR="/mnt/ext1/system/fonts"

# shellcheck disable=2000
if [ "$(echo "$@" | wc -c)" -eq 1 ]; then
    args="/mnt/ext1/"
else
    args="$*"
fi

# we keep maximum 500K worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

RETURN_VALUE=85
while [ ${RETURN_VALUE} -eq 85 ]; do
    ./reader.lua "${args}" >>crash.log 2>&1
    RETURN_VALUE=$?
done

if pidof reader.lua >/dev/null 2>&1; then
    killall -TERM reader.lua
fi

exit ${RETURN_VALUE}
