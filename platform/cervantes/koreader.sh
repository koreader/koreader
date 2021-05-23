#!/bin/bash

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
        # Setup the FBInk daemon
        export FBINK_NAMED_PIPE="/tmp/koreader.fbink"
        rm -f "${FBINK_NAMED_PIPE}"
        FBINK_PID="$(./fbink --daemon 1 %KOREADER% -q -y -6 -P 0)"
        # NOTE: See frontend/ui/otamanager.lua for a few more details on how we squeeze a percentage out of tar's checkpoint feature
        # NOTE: %B should always be 512 in our case, so let stat do part of the maths for us instead of using %s ;).
        FILESIZE="$(stat -c %b "${NEWUPDATE}")"
        BLOCKS="$((FILESIZE / 20))"
        export CPOINTS="$((BLOCKS / 100))"
        # shellcheck disable=SC2016
        ./tar xf "${NEWUPDATE}" --strip-components=1 --no-same-permissions --no-same-owner --checkpoint="${CPOINTS}" --checkpoint-action=exec='printf "%s" $((TAR_CHECKPOINT / CPOINTS)) > ${FBINK_NAMED_PIPE}'
        fail=$?
        kill -TERM "${FBINK_PID}"
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
        rm -f "${NEWUPDATE}" # always purge newupdate to prevent update loops
        unset CPOINTS FBINK_NAMED_PIPE
        unset BLOCKS FILESIZE FBINK_PID
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

CRASH_COUNT=0
CRASH_TS=0
CRASH_PREV_TS=0
# **magic** values to request shell stuff. It starts at 85,
# any number lower than that will exit this script.
RESTART_KOREADER=85
ENTER_USBMS=86
ENTER_QBOOKAPP=87
RETURN_VALUE="${RESTART_KOREADER}"

# Loop forever until KOReader requests a normal exit.
while [ "${RETURN_VALUE}" -ne 0 ]; do

    # move dictionaries from external storage to koreader private partition.
    find /mnt/public/dict -type f -exec mv -v \{\} /mnt/private/koreader/data/dict \; 2>/dev/null

    if [ ${RETURN_VALUE} -eq ${RESTART_KOREADER} ]; then
        # Do an update check now, so we can actually update KOReader via the "Restart KOReader" menu entry ;).
        ko_update_check
    fi

    # run KOReader
    ./reader.lua "$@" >>crash.log 2>&1
    RETURN_VALUE=$?

    if [ ${RETURN_VALUE} -ne 0 ] && [ "${RETURN_VALUE}" -ne "${ENTER_USBMS}" ] && [ "${RETURN_VALUE}" -ne "${ENTER_QBOOKAPP}" ] && [ "${RETURN_VALUE}" -ne "${RESTART_KOREADER}" ]; then
        # Increment the crash counter
        CRASH_COUNT=$((CRASH_COUNT + 1))
        CRASH_TS=$(date +'%s')
        # Reset it to a first crash if it's been a while since our last crash...
        if [ $((CRASH_TS - CRASH_PREV_TS)) -ge 20 ]; then
            CRASH_COUNT=1
        fi

        # Check if the user requested to always abort on crash
        if grep -q '\["dev_abort_on_crash"\] = true' 'settings.reader.lua' 2>/dev/null; then
            ALWAYS_ABORT="true"
            # In which case, make sure we pause on *every* crash
            CRASH_COUNT=1
        else
            ALWAYS_ABORT="false"
        fi

        # Show a fancy bomb on screen
        viewWidth=600
        viewHeight=800
        FONTH=16
        eval "$(./fbink -e | tr ';' '\n' | grep -e viewWidth -e viewHeight -e FONTH | tr '\n' ';')"
        # Compute margins & sizes relative to the screen's resolution, so we end up with a similar layout, no matter the device.
        # Height @ ~56.7%, w/ a margin worth 1.5 lines
        bombHeight=$((viewHeight / 2 + viewHeight / 15))
        bombMargin=$((FONTH + FONTH / 2))
        # With a little notice at the top of the screen, on a big gray screen of death ;).
        ./fbink -q -b -c -B GRAY9 -m -y 1 "Don't Panic! (Crash n°${CRASH_COUNT} -> ${RETURN_VALUE})"
        if [ ${CRASH_COUNT} -eq 1 ]; then
            # Warn that we're waiting on a tap to continue...
            ./fbink -q -b -O -m -y 2 "Tap the screen to continue."
        fi
        # U+1F4A3, the hard way, because we can't use \u or \U escape sequences...
        ./fbink -q -b -O -m -t regular=./fonts/freefont/FreeSerif.ttf,px=${bombHeight},top=${bombMargin} -- $'\xf0\x9f\x92\xa3'
        # And then print the tail end of the log on the bottom of the screen...
        crashLog="$(tail -n 25 crash.log | sed -e 's/\t/    /g')"
        # The idea for the margins being to leave enough room for an fbink -Z bar, small horizontal margins, and a font size based on what 6pt looked like @ 265dpi
        ./fbink -q -b -O -t regular=./fonts/droid/DroidSansMono.ttf,top=$((viewHeight / 2 + FONTH * 2 + FONTH / 2)),left=$((viewWidth / 60)),right=$((viewWidth / 60)),px=$((viewHeight / 64)) -- "${crashLog}"
        # So far, we hadn't triggered an actual screen refresh, do that now, to make sure everything is bundled in a single flashing refresh.
        ./fbink -q -f -s
        # Cue a lemming's faceplant sound effect!

        {
            echo "!!!!"
            echo "Uh oh, something went awry... (Crash n°${CRASH_COUNT}: $(date +'%x @ %X'))"
            echo "Running on Linux $(uname -r) ($(uname -v))"
        } >>crash.log 2>&1
        if [ ${CRASH_COUNT} -lt 5 ] && [ "${ALWAYS_ABORT}" = "false" ]; then
            echo "Attempting to restart KOReader . . ." >>crash.log 2>&1
            echo "!!!!" >>crash.log 2>&1
        fi

        # Pause a bit if it's the first crash in a while, so that it actually has a chance of getting noticed ;).
        if [ ${CRASH_COUNT} -eq 1 ]; then
            # NOTE: We don't actually care about what head reads, we're just using it as a fancy sleep ;).
            #       i.e., we pause either until the 15s timeout, or until the user touches the screen.
            timeout 15 head -c 24 /dev/input/event1 >/dev/null
        fi
        # Cycle the last crash timestamp
        CRASH_PREV_TS=${CRASH_TS}

        # But if we've crashed more than 5 consecutive times, exit, because we wouldn't want to be stuck in a loop...
        # NOTE: No need to check for ALWAYS_ABORT, CRASH_COUNT will always be 1 when it's true ;).
        if [ ${CRASH_COUNT} -ge 5 ]; then
            echo "Too many consecutive crashes, aborting . . ." >>crash.log 2>&1
            echo "!!!! ! !!!!" >>crash.log 2>&1
            break
        fi

        # If the user requested to always abort on crash, do so.
        if [ "${ALWAYS_ABORT}" = "true" ]; then
            echo "Aborting . . ." >>crash.log 2>&1
            echo "!!!! ! !!!!" >>crash.log 2>&1
            break
        fi
    else
        # Reset the crash counter if that was a sane exit/restart
        CRASH_COUNT=0
    fi

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
