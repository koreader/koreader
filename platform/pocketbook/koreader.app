#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR=/mnt/ext1/applications/koreader

# file through which we communicate instanced opens
export KO_PATH_OPEN_BOOK=/tmp/.koreader.open

# check for and notify a running instance
INSTANCE_PID=$(cat /tmp/koreader.pid 2> /dev/null)
if [ "${INSTANCE_PID}" != "" ] && [ -e "/proc/${INSTANCE_PID}" ]; then
    echo "$@" > "${KO_PATH_OPEN_BOOK}"
    exec /usr/bin/iv2sh SetActiveTask "${INSTANCE_PID}" 0
fi

# we're first, so publish our instance
echo $$ > /tmp/koreader.pid

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

export KO_EXIT_CODE="/tmp/.koreader.exit"
RETURN_VALUE="85"
while [ "${RETURN_VALUE}" = "85" ]; do
    rm -f "${KO_EXIT_CODE}"
    ./reader.lua "${args}" >>crash.log 2>&1
    RETURN_VALUE=$(cat ${KO_EXIT_CODE})
done

rm -f /tmp/koreader.pid

if pidof reader.lua >/dev/null 2>&1; then
    killall -TERM reader.lua
fi

exit "${RETURN_VALUE}"
