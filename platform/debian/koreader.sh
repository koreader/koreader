#!/bin/bash
export LC_ALL="en_US.UTF-8"

# writable storage: ${HOME}/.config/koreader.
export KO_MULTIUSER=1

if [ -z "${1}" ]; then
    ARGS="${HOME}"
else
    if [ $# -eq 1 ] && [ -e "$(pwd)/${1}" ]; then
        ARGS="$(pwd)/${1}"
    else
        ARGS="${*}"
    fi
fi

# working directory of koreader
KOREADER_DIR="/usr/lib/koreader"

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

# export load library path
export LD_LIBRARY_PATH=${KOREADER_DIR}/libs:$LD_LIBRARY_PATH

# export external font directory
export EXT_FONT_DIR="${HOME}/.config/koreader/fonts"
[ ! -d "${EXT_FONT_DIR}" ] && mkdir -pv "${EXT_FONT_DIR}"

RETURN_VALUE=85
while [ $RETURN_VALUE -eq 85 ]; do
    ./reader.lua "${ARGS}"
    RETURN_VALUE=$?
    # do not restart with saved arguments
    ARGS="${HOME}"
done

# remove the flag to avoid emulator confusion
export -n KO_MULTIUSER

exit $RETURN_VALUE

