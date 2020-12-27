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
        ./fbink -q -y -7 -pmh "Updating KOReader"
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
            ./fbink -q -y -6 -pm "Update successful :)"
            ./fbink -q -y -5 -pm "KOReader will start momentarily . . ."
        else
            # Huh ho...
            ./fbink -q -y -6 -pmh "Update failed :("
            ./fbink -q -y -5 -pm "KOReader may fail to function properly!"
        fi
        rm -f "${NEWUPDATE}" # always purge newupdate in all cases to prevent update loop
        unset BLOCKS CPOINTS
        # Ensure everything is flushed to disk before we restart. This *will* stall for a while on slow storage!
        sync
    fi
}

# NOTE: Keep doing an initial update check, in addition to one during the restart loop, so we can pickup potential updates of this very script...
ko_update_check
# If an update happened, and was successful, reexec
if [ -n "${fail}" ] && [ "${fail}" -eq 0 ]; then
    # By now, we know we're in the right directory, and our script name is pretty much set in stone, so we can forgo using $0
    exec ./koreader.sh "$@"
fi

# load our own shared libraries if possible
export LD_LIBRARY_PATH="${KOREADER_DIR}/libs"

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# export external font directory
export EXT_FONT_DIR="/usr/lib/fonts"

# we keep at most 500k worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

# check if QBookApp was started before us, then
# restart the application after leaving KOReader
export STANDALONE="true"
if pkill -0 QBookApp; then
    STANDALONE="false"
fi

if [ "${STANDALONE}" != "true" ]; then
    stopapp.sh >/dev/null 2>&1
    [ -x /etc/init.d/connman ] && /etc/init.d/connman stop
fi

# **magic** values to request shell stuff. It starts at 85,
# any number lower than that will exit this script.
RESTART_KOREADER=85
ENTER_USBMS=86
ENTER_QBOOKAPP=87
RETURN_VALUE="${RESTART_KOREADER}"

# Loop forever until KOReader requests a normal exit.
while [ "${RETURN_VALUE}" -ge "${RESTART_KOREADER}" ]; do

    # move dictionaries from external storage to koreader private partition.
    find /mnt/public/dict -type f -exec mv -v \{\} /mnt/private/koreader/data/dict \; 2>/dev/null

    # Do an update check now, so we can actually update KOReader via the "Restart KOReader" menu entry ;).
    ko_update_check

    # run KOReader
    ./reader.lua "$@" >>crash.log 2>&1
    RETURN_VALUE=$?

    # check if KOReader requested to enter in mass storage mode.
    if [ "${RETURN_VALUE}" -eq "${ENTER_USBMS}" ]; then
        # NOTE: at this point we're sure that the safemode tool
        # is recent enough to support the "--force" flag.

        safemode storage --force 2>/dev/null
        # waiting forever for home button events.

    elif [ "${RETURN_VALUE}" -eq "${ENTER_QBOOKAPP}" ]; then
        ./release-ip.sh
        ./disable-wifi.sh
        [ -x /etc/init.d/connman ] && /etc/init.d/connman start

        # (re)start the reading application in the background
        restart.sh >/dev/null 2>&1
        sleep 2

        # loop while BQ app is running.
        while pkill -0 QBookApp; do
            sleep 10
        done
    fi
done

if [ "${STANDALONE}" != "true" ]; then
    ./release-ip.sh
    ./disable-wifi.sh
    [ -x /etc/init.d/connman ] && /etc/init.d/connman start
    restart.sh >/dev/null 2>&1
fi
