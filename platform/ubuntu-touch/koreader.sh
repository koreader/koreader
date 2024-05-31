#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR="${0%/*}"

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

# export external font directory
export EXT_FONT_DIR="${HOME}/fonts"

# set fullscreen mode
export SDL_FULLSCREEN=1

RETURN_VALUE=85

while [ ${RETURN_VALUE} -eq 85 ]; do
    ./reader.lua -d
    RETURN_VALUE=$?
done

exit ${RETURN_VALUE}
