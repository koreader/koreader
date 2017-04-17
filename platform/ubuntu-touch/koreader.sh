#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR="${0%/*}"

# update to new version from OTA directory
NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
if [ -f "${NEWUPDATE}" ]; then
    # TODO: any graphic indication for the updating progress?
    cd .. && tar xf "${NEWUPDATE}" && mv "${NEWUPDATE}" "${INSTALLED}"
fi

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

# export load library path for some old firmware
export LD_LIBRARY_PATH=${KOREADER_DIR}/libs:$LD_LIBRARY_PATH

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export external font directory
export EXT_FONT_DIR="${HOME}/fonts"

# set fullscreen mode
export SDL_FULLSCREEN=1

RETURN_VALUE=85

while [ $RETURN_VALUE -eq 85 ]; do
    ./reader.lua -d ~/Documents
    RETURN_VALUE=$?
done

exit $RETURN_VALUE
