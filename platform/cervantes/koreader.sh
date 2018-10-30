#!/bin/sh

export LC_ALL="en_US.UTF-8"

# working directory of koreader
KOREADER_DIR="${0%/*}"

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

# update to new version from OTA directory
ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
    INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
    if [ -f "${NEWUPDATE}" ]; then
        #./fbink -q -y -7 -pmh "Updating KOReader"
        # NOTE: See frontend/ui/otamanager.lua for a few more details on how we squeeze a percentage out of tar's checkpoint feature
        # NOTE: %B should always be 512 in our case, so let stat do part of the maths for us instead of using %s ;).
        FILESIZE="$(stat -c %b "${NEWUPDATE}")"
        BLOCKS="$((FILESIZE / 20))"
        export CPOINTS="$((BLOCKS / 100))"
        # shellcheck disable=SC2016
        ./tar xf "${NEWUPDATE}" --strip-components=1 --no-same-permissions --no-same-owner --checkpoint="${CPOINTS}" --checkpoint-action=exec='./fbink -q -y -6 -P $(($TAR_CHECKPOINT/$CPOINTS))'
        fail=$?
        # Cleanup behind us...
        if [ "${fail}" -eq 0 ]; then
            mv "${NEWUPDATE}" "${INSTALLED}"
            #    ./fbink -q -y -6 -pm "Update successful :)"
            #    ./fbink -q -y -5 -pm "KOReader will start momentarily . . ."
            #else
            #    # Huh ho...
            #    ./fbink -q -y -6 -pmh "Update failed :("
            #    ./fbink -q -y -5 -pm "KOReader may fail to function properly!"
        fi
        rm -f "${NEWUPDATE}" # always purge newupdate in all cases to prevent update loop
        unset BLOCKS CPOINTS
    fi
}

# if no args were passed to the script, start the FM on public partition.
if [ "$#" -eq 0 ]; then
    args="/mnt/public"
else
    args="$*"
fi

# NOTE: Keep doing an initial update check, in addition to one during the restart loop, so we can pickup potential updates of this very script...
ko_update_check
# If an update happened, and was successful, reexec
if [ -n "${fail}" ] && [ "${fail}" -eq 0 ]; then
    # By now, we know we're in the right directory, and our script name is pretty much set in stone, so we can forgo using $0
    exec ./koreader.sh "${args}"
fi

# load our own shared libraries if possible
export LD_LIBRARY_PATH="${KOREADER_DIR}/libs"

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# we keep at most 500k worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

# check if QBookApp was started before us, then
# restart the application after leaving KOReader
export STANDALONE="true"
if pkill -0 QBookpp; then
    STANDALONE="false"
fi

if [ "${STANDALONE}" != "true" ]; then
    stopapp.sh >/dev/null 2>&1
fi

RETURN_VALUE=85
while [ "${RETURN_VALUE}" -eq 85 ]; do
    ./reader.lua "${args}" >>crash.log 2>&1
    RETURN_VALUE=$?
done

if [ "${STANDALONE}" != "true" ]; then
    restart.sh >/dev/null 2>&1
fi
