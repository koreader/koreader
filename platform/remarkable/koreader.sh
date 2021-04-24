#!/bin/sh
export LC_ALL="en_US.UTF-8"
# working directory of koreader
KOREADER_DIR="${0%/*}"

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

# reMarkable 2 check
IFS= read -r MACHINE_TYPE <"/sys/devices/soc0/machine"
if [ "reMarkable 2.0" = "${MACHINE_TYPE}" ]; then
    if [ -z "${RM2FB_SHIM}" ]; then
        echo "reMarkable 2 requires RM2FB to work, visit https://github.com/ddvk/remarkable2-framebuffer for instructions how to setup"
        exit 1
    fi
    export KO_DONT_GRAB_INPUT=1
fi

# update to new version from OTA directory
ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/koreader.updated.tar"
    INSTALLED="${KOREADER_DIR}/ota/koreader.installed.tar"
    if [ -f "${NEWUPDATE}" ]; then
        # If button-listen service is running then stop it during update so that
        # the update can overwite the binary
        systemctl is-active --quiet button-listen
        USING_BUTTON_LISTEN=$?
        if [ ${USING_BUTTON_LISTEN} -eq 0 ]; then
            systemctl stop button-listen
        fi

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
            # Uh oh...
            ./fbink -q -y -6 -pmh "Update failed :("
            ./fbink -q -y -5 -pm "KOReader may fail to function properly!"
        fi
        rm -f "${NEWUPDATE}" # always purge newupdate to prevent update loops
        unset CPOINTS FBINK_NAMED_PIPE
        unset BLOCKS FILESIZE FBINK_PID
        # Ensure everything is flushed to disk before we restart. This *will* stall for a while on slow storage!
        busybox sync

        if [ ${USING_BUTTON_LISTEN} -eq 0 ]; then
            systemctl start button-listen
        fi
    fi
}
# NOTE: Keep doing an initial update check, in addition to one during the restart loop, so we can pickup potential updates of this very script...
ko_update_check
# If an update happened, and was successful, reexec
if [ -n "${fail}" ] && [ "${fail}" -eq 0 ]; then
    # By now, we know we're in the right directory, and our script name is pretty much set in stone, so we can forgo using $0
    exec ./koreader.sh "${@}"
fi

# load our own shared libraries if possible
export LD_LIBRARY_PATH="${KOREADER_DIR}/libs:${LD_LIBRARY_PATH}"

# export trained OCR data directory
export TESSDATA_PREFIX="data"

# export dict directory
export STARDICT_DATA_DIR="data/dict"

# We'll want to ensure Portrait rotation to allow us to use faster blitting codepaths @ 8bpp,
# so remember the current one before fbdepth does its thing.
ORIG_FB_ROTA="$(./fbdepth -o)"
# In the same vein, swap to 8bpp,
# because 16bpp is the worst idea in the history of time, as RGB565 is generally a PITA without hardware blitting,
# and 32bpp usually gains us nothing except a performance hit (we're not Qt5 with its QPainter constraints).
# The reduced size & complexity should hopefully make things snappier,
# (and hopefully prevent the JIT from going crazy on high-density screens...).
# NOTE: Even though both pickel & Nickel appear to restore their preferred fb setup, we'll have to do it ourselves,
#       as they fail to flip the grayscale flag properly. Plus, we get to play nice with every launch method that way.
#       So, remember the current bitdepth, so we can restore it on exit.
ORIG_FB_BPP="$(./fbdepth -g)"
echo "Original fb settings: bitdepth = ${ORIG_FB_BPP}, rotation = ${ORIG_FB_ROTA}" >>crash.log 2>&1

# Sanity check...
case "${ORIG_FB_BPP}" in
    8) ;;
    16) ;;
    32) ;;
    *)
        # Uh oh? Don't do anything...
        unset ORIG_FB_BPP
        ;;
esac

# The actual swap is done in a function, because we can disable it in the Developer settings, and we want to honor it on restart.
ko_do_fbdepth() {
    if [ -n "${KO_DONT_SET_DEPTH}" ]; then
        return
    fi

    # Check if the swap has been disabled...
    if grep -q '\["dev_startup_no_fbdepth"\] = true' 'settings.reader.lua' 2>/dev/null; then
        # Swap back to the original bitdepth (in case this was a restart)
        if [ -n "${ORIG_FB_BPP}" ]; then

            echo "Making sure we're using the original fb bitdepth @ ${ORIG_FB_BPP}bpp & rotation @ ${ORIG_FB_ROTA}" >>crash.log 2>&1
            ./fbdepth -d "${ORIG_FB_BPP}" -r "${ORIG_FB_ROTA}" >>crash.log 2>&1
        fi
    else
        # Swap to 8bpp if things look sane
        if [ -n "${ORIG_FB_BPP}" ]; then
            echo "Switching fb bitdepth to 8bpp & rotation to Portrait" >>crash.log 2>&1
            ./fbdepth -d 8 -r 1 >>crash.log 2>&1
        fi
    fi
}

# we keep at most 500KB worth of crash log
if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

CRASH_COUNT=0
CRASH_TS=0
CRASH_PREV_TS=0
# Because we *want* an initial fbdepth pass ;).
RETURN_VALUE=85
while [ ${RETURN_VALUE} -ne 0 ]; do
    # 85 is what we return when asking for a KOReader restart
    if [ ${RETURN_VALUE} -eq 85 ]; then
        # Do an update check now, so we can actually update KOReader via the "Restart KOReader" menu entry ;).
        ko_update_check
        # Do or double-check the fb depth switch, or restore original bitdepth if requested
        ko_do_fbdepth
    fi

    ./reader.lua "$@" >>crash.log 2>&1
    RETURN_VALUE=$?

    # Did we crash?
    if [ ${RETURN_VALUE} -ne 0 ] && [ ${RETURN_VALUE} -ne 85 ]; then
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
            # Warn that we're sleeping for a bit...
            ./fbink -q -b -O -m -y 2 "KOReader will restart in 15 sec."
        fi
        # U+1F4A3, the hard way, because we can't use \u or \U escape sequences...
        # shellcheck disable=SC2039,SC3003
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

# Restore original fb bitdepth if need be...
# Since we also (almost) always enforce Portrait, we also have to restore the original rotation no matter what ;).
if [ -n "${ORIG_FB_BPP}" ]; then
    echo "Restoring original fb bitdepth @ ${ORIG_FB_BPP}bpp & rotation @ ${ORIG_FB_ROTA}" >>crash.log 2>&1
    ./fbdepth -d "${ORIG_FB_BPP}" -r "${ORIG_FB_ROTA}" >>crash.log 2>&1
else
    echo "Restoring original fb rotation @ ${ORIG_FB_ROTA}" >>crash.log 2>&1
    ./fbdepth -r "${ORIG_FB_ROTA}" >>crash.log 2>&1
fi

exit ${RETURN_VALUE}
