#!/bin/sh
export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR="/mnt/ext1/applications/koreader"

# file through which we communicate instanced opens
export KO_PATH_OPEN_BOOK="/tmp/.koreader.open"

# check for and notify a running instance
INSTANCE_PID=$(cat /tmp/koreader.pid 2>/dev/null)
if [ "${INSTANCE_PID}" != "" ] && [ -e "/proc/${INSTANCE_PID}" ]; then
    echo "$@" >"${KO_PATH_OPEN_BOOK}"
    exec /usr/bin/iv2sh SetActiveTask "${INSTANCE_PID}" 0
fi

# we're first, so publish our instance
echo $$ >/tmp/koreader.pid

# update to new version from OTA directory
ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
    INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
    if [ -f "${NEWUPDATE}" ]; then
        "${KOREADER_DIR}/fbink" -q -y -7 -pmh "Updating KOReader"
        # NOTE: See frontend/ui/otamanager.lua for a few more details on how we squeeze a percentage out of tar's checkpoint feature
        # NOTE: %B should always be 512 in our case, so let stat do part of the maths for us instead of using %s ;).
        FILESIZE="$(stat -c %b "${NEWUPDATE}")"
        BLOCKS="$((FILESIZE / 20))"
        export CPOINTS="$((BLOCKS / 100))"
        # shellcheck disable=SC2016
        cd /mnt/ext1 && "${KOREADER_DIR}/tar" xf "${NEWUPDATE}" --no-same-permissions --no-same-owner --checkpoint="${CPOINTS}" --checkpoint-action=exec='${KOREADER_DIR}/fbink -q -y -6 -P $(($TAR_CHECKPOINT/$CPOINTS))'
        fail=$?
        # Cleanup behind us...
        if [ "${fail}" -eq 0 ]; then
            mv "${NEWUPDATE}" "${INSTALLED}"
            "${KOREADER_DIR}/fbink" -q -y -6 -pm "Update successful :)"
            "${KOREADER_DIR}/fbink" -q -y -5 -pm "KOReader will start momentarily . . ."
        else
            # Uh oh...
            "${KOREADER_DIR}/fbink" -q -y -6 -pmh "Update failed :("
            "${KOREADER_DIR}/fbink" -q -y -5 -pm "KOReader may fail to function properly!"
        fi
        rm -f "${NEWUPDATE}" # always purge newupdate in all cases to prevent update loop
        unset BLOCKS CPOINTS
        # Ensure everything is flushed to disk before we restart. This *will* stall for a while on slow storage!
        sync
    fi
}
# NOTE: Keep doing an initial update check, in addition to one during the restart loop, so we can pickup potential updates of this very script...
ko_update_check

# we're always starting from our working directory
cd ${KOREADER_DIR} || exit

# export load library path for some old firmware
export LD_LIBRARY_PATH="${KOREADER_DIR}/libs:${LD_LIBRARY_PATH}"

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

# we keep at maximum 500K worth of crash log
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

rm -f "/tmp/koreader.pid"

if pidof reader.lua >/dev/null 2>&1; then
    killall -TERM reader.lua
fi

exit "${RETURN_VALUE}"
