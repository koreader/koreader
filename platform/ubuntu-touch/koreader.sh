#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR="${0%/*}"

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

# export load library path for some old firmware
export LD_LIBRARY_PATH=${KOREADER_DIR}/libs:${LD_LIBRARY_PATH}

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export external font directory
export EXT_FONT_DIR="${HOME}/fonts"

# set fullscreen mode
export SDL_FULLSCREEN=1

RETURN_VALUE=85

while [ ${RETURN_VALUE} -eq 85 ]; do
    ./reader.lua -d ~/Documents
    RETURN_VALUE=$?
done

exit ${RETURN_VALUE}
