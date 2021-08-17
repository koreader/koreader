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

# try to bring in raw device input (on rooted devices)
/mnt/secure/su /bin/chmod 644 /dev/input/*

# we're first, so publish our instance
echo $$ >/tmp/koreader.pid

# update to new version from OTA directory
ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
    INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
    if [ -f "${NEWUPDATE}" ]; then
        "${KOREADER_DIR}/fbink" -q -y -7 -pmh "Updating KOReader"
        # Setup the FBInk daemon
        export FBINK_NAMED_PIPE="/tmp/.koreader.fbink"
        rm -f "${FBINK_NAMED_PIPE}"
        FBINK_PID="$("${KOREADER_DIR}/fbink" --daemon 1 %KOREADER% -q -y -6 -P 0)"
        # NOTE: See frontend/ui/otamanager.lua for a few more details on how we squeeze a percentage out of tar's checkpoint feature
        # NOTE: %B should always be 512 in our case, so let stat do part of the maths for us instead of using %s ;).
        FILESIZE="$(stat -c %b "${NEWUPDATE}")"
        # shellcheck disable=SC2003
        BLOCKS="$(expr "${FILESIZE}" / 20)"
        # shellcheck disable=SC2003
        CPOINTS="$(expr "${BLOCKS}" / 100)"
        export CPOINTS
        # NOTE: We don't run as root, but folders created over USBMS are owned by root, which yields fun permission shenanigans...
        #       c.f., https://github.com/koreader/koreader/issues/7581
        KO_PB_TARLOG="/tmp/.koreader.tar"
        # shellcheck disable=SC2016
        "${KOREADER_DIR}/tar" --no-same-permissions --no-same-owner --checkpoint="${CPOINTS}" --checkpoint-action=exec='printf "%s" $(expr ${TAR_CHECKPOINT} / ${CPOINTS}) > ${FBINK_NAMED_PIPE}' -C "/mnt/ext1" -xf "${NEWUPDATE}" 2>"${KO_PB_TARLOG}"
        fail=$?
        kill -TERM "${FBINK_PID}"
        # As mentioned above, filter out potential chmod & utime failures...
        if [ "${fail}" -ne 0 ]; then
            if [ "$(grep -Evc '(Cannot utime|Cannot change mode|Exiting with failure status due to previous errors)' "${KO_PB_TARLOG}")" -eq "0" ]; then
                # No other errors, we're good!
                fail=0
            fi
        fi
        rm -f "${KO_PB_TARLOG}"
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
        rm -f "${NEWUPDATE}" # always purge newupdate to prevent update loops
        unset CPOINTS FBINK_NAMED_PIPE
        unset BLOCKS FILESIZE FBINK_PID
        # Ensure everything is flushed to disk before we restart. This *will* stall for a while on slow storage!
        sync
    fi
}

# we're always starting from our working directory
cd ${KOREADER_DIR} || exit

# export load library path for some old firmware
export LD_LIBRARY_PATH="${KOREADER_DIR}/libs:${LD_LIBRARY_PATH}"

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# we keep at maximum 500K worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

export KO_EXIT_CODE="/tmp/.koreader.exit"
CRASH_COUNT=0
CRASH_TS=0
CRASH_PREV_TS=0
# List of supported special return codes
KO_RC_RESTART=85
#KO_RC_USBMS=86
# Ensure a clean slate on startup
rm -f "${KO_EXIT_CODE}"
RETURN_VALUE=${KO_RC_RESTART}
while [ "${RETURN_VALUE}" -ne 0 ]; do
    if [ "${RETURN_VALUE}" -eq ${KO_RC_RESTART} ]; then
        # Do an update check now, so we can actually update KOReader via the "Restart KOReader" menu entry ;).
        ko_update_check
    fi

    ./reader.lua "$@" >>crash.log 2>&1

    # Account for the fact a hard crash may have prevented the KO_EXIT_CODE file from being written to...
    if [ -f "${KO_EXIT_CODE}" ]; then
        RETURN_VALUE="$(cat ${KO_EXIT_CODE})"
        rm -f "${KO_EXIT_CODE}"
    else
        # If we couldn't find it, something went horribly wrong ;).
        RETURN_VALUE=42
    fi

    # Did we crash?
    if [ "${RETURN_VALUE}" -ne 0 ] && [ "${RETURN_VALUE}" -ne ${KO_RC_RESTART} ]; then
        # Increment the crash counter
        # shellcheck disable=SC2003
        CRASH_COUNT="$(expr ${CRASH_COUNT} + 1)"
        CRASH_TS="$(date +'%s')"
        # Reset it to a first crash if it's been a while since our last crash...
        # shellcheck disable=SC2003
        if [ "$(expr "${CRASH_TS}" - "${CRASH_PREV_TS}")" -ge 20 ]; then
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
        eval "$("${KOREADER_DIR}/fbink" -e | tr ';' '\n' | grep -e viewWidth -e viewHeight -e FONTH | tr '\n' ';')"
        # Compute margins & sizes relative to the screen's resolution, so we end up with a similar layout, no matter the device.
        # Height @ ~56.7%, w/ a margin worth 1.5 lines
        # shellcheck disable=SC2003
        bombHeight="$(expr ${viewHeight} / 2 + ${viewHeight} / 15)"
        # shellcheck disable=SC2003
        bombMargin="$(expr ${FONTH} + ${FONTH} / 2)"
        # With a little notice at the top of the screen, on a big gray screen of death ;).
        "${KOREADER_DIR}/fbink" -q -b -c -B GRAY9 -m -y 1 "Don't Panic! (Crash n°${CRASH_COUNT} -> ${RETURN_VALUE})"
        if [ ${CRASH_COUNT} -eq 1 ]; then
            # Warn that we're sleeping for a bit...
            "${KOREADER_DIR}/fbink" -q -b -O -m -y 2 "KOReader will restart in 15 sec."
        fi
        # U+1F4A3, the hard way, because we can't use \u or \U escape sequences...
        # shellcheck disable=SC2039,SC3003
        "${KOREADER_DIR}/fbink" -q -b -O -m -t regular=${KOREADER_DIR}/fonts/freefont/FreeSerif.ttf,px="${bombHeight}",top="${bombMargin}" -- $'\xf0\x9f\x92\xa3'
        # And then print the tail end of the log on the bottom of the screen...
        crashLog="$(tail -n 25 crash.log | sed -e 's/\t/    /g')"
        # The idea for the margins being to leave enough room for an fbink -Z bar, small horizontal margins, and a font size based on what 6pt looked like @ 265dpi
        # shellcheck disable=SC2003
        "${KOREADER_DIR}/fbink" -q -b -O -t regular=${KOREADER_DIR}/fonts/droid/DroidSansMono.ttf,top="$(expr ${viewHeight} / 2 + ${FONTH} '*' 2 + ${FONTH} / 2)",left="$(expr ${viewWidth} / 60)",right="$(expr ${viewWidth} / 60)",px="$(expr ${viewHeight} / 64)" -- "${crashLog}"
        # So far, we hadn't triggered an actual screen refresh, do that now, to make sure everything is bundled in a single flashing refresh.
        ${KOREADER_DIR}/fbink -q -f -s
        # Cue a lemming's faceplant sound effect!

        {
            echo "!!!!"
            echo "Uh oh, something went awry... (Crash n°${CRASH_COUNT}: $(date +'%x @ %X'))"
        } >>crash.log 2>&1
        if [ ${CRASH_COUNT} -lt 5 ] && [ "${ALWAYS_ABORT}" = "false" ]; then
            echo "Attempting to restart KOReader . . ." >>crash.log 2>&1
            echo "!!!!" >>crash.log 2>&1
        fi

        # Pause a bit if it's the first crash in a while, so that it actually has a chance of getting noticed ;).
        if [ ${CRASH_COUNT} -eq 1 ]; then
            sleep 15
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
done

rm -f "/tmp/koreader.pid"

if pidof reader.lua >/dev/null 2>&1; then
    killall -TERM reader.lua
fi

exit "${RETURN_VALUE}"
