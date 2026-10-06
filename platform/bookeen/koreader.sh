#!/bin/sh
#
# KOReader launcher for Bookeen Cybook devices.
# The install directory must be the working directory because KOReader and
# Bookeen helper scripts use relative paths. The stock /bin/eink provides
# crash feedback.
export LC_ALL="en_US.UTF-8"

# Draw a stock Bookeen BMP to the panel when available.
ko_splash() {
    [ -x /bin/eink ] && [ -e "$1" ] && /bin/eink d "$1" >/dev/null 2>&1
}

if [ -z "${KOREADER_DIR}" ]; then
    if KOREADER_DIR="$(dirname "$(realpath "$0")" 2>/dev/null)" && [ -n "${KOREADER_DIR}" ]; then
        :
    else
        # Support Bookeen images without the realpath applet.
        KOREADER_DIR="$(cd "$(dirname "$0")" && pwd -P)"
    fi
fi
export KOREADER_DIR
UNPACK_DIR="${KOREADER_DIR%/*}"

for arg; do
    shift
    if [ -e "${PWD}/${arg}" ]; then
        arg="${PWD}/${arg}"
    fi
    set -- "$@" "${arg}"
done

if [ "$(dirname "$0")" != '/tmp' ]; then
    cp -pf "$0" '/tmp/koreader.sh' || exit 1
    chmod 755 '/tmp/koreader.sh'
    exec '/tmp/koreader.sh' "$@"
fi

cd "${KOREADER_DIR}" || exit 1

if [ -e crash.log ]; then
    tail -c 500000 crash.log >crash.log.new
    mv -f crash.log.new crash.log
fi

if [ ! -x ./reader.lua ] || [ ! -x ./luajit ]; then
    echo "koreader.sh: ${KOREADER_DIR} is not a usable install (missing reader.lua or luajit)" >>crash.log 2>&1
    ko_splash /system/update_finished_error.bmp
    exit 1
fi

ko_update_check() {
    NEWUPDATE="${KOREADER_DIR}/ota/update.tar.xz"
    if [ -f "${NEWUPDATE}" ]; then
        echo "[$(date)] koreader.sh: applying update from ${NEWUPDATE}" >>crash.log 2>&1
        cp "${KOREADER_DIR}/ota/package.index" /tmp/package.index 2>/dev/null
        (cd "${UNPACK_DIR}" && "${KOREADER_DIR}/unpack" -X "${NEWUPDATE}" >>"${KOREADER_DIR}/crash.log" 2>&1)
        fail=$?
        if [ "${fail}" -eq 0 ]; then
            if [ -f /tmp/package.index ] && [ -f "${KOREADER_DIR}/ota/package.index" ]; then
                grep -x -v -F -f "${KOREADER_DIR}/ota/package.index" /tmp/package.index 2>/dev/null |
                    while IFS= read -r leftover; do
                        [ -n "${leftover}" ] && rm -f "${UNPACK_DIR}/${leftover}"
                    done
            fi
            echo "[$(date)] koreader.sh: update successful" >>crash.log 2>&1
        else
            echo "[$(date)] koreader.sh: update FAILED (${fail}); KOReader may not function properly" >>crash.log 2>&1
        fi
        # Always purge the payload to prevent an update loop.
        rm -f /tmp/package.index "${NEWUPDATE}"
        # Flush the update before restarting.
        sync
    fi
}

ko_update_check
if [ -n "${fail}" ] && [ "${fail}" -eq 0 ]; then
    exec ./koreader.sh "$@"
fi

export STARDICT_DATA_DIR="data/dict"

# User fonts live on Bookeen's FAT user partition.
export EXT_FONT_DIR="/mnt/fat/fonts"

# Optionally stop the Bookeen supervisor while KOReader runs. This is disabled
# by default because the existing setup works without it and stopping ebrmain
# can leave the device without a reader. Do not use it through the boordr shim:
# ebrmain is then KOReader's parent and must receive the shim's exit code.
VIA_EBRMAIN="false"
if [ -n "${KO_STOP_EBRMAIN}" ] && [ -n "${KO_VIA_BOORDR_SHIM}" ]; then
    echo "[$(date)] koreader.sh: ignoring KO_STOP_EBRMAIN -- started via the boordr shim, ebrmain is our parent" >>crash.log 2>&1
elif [ -n "${KO_STOP_EBRMAIN}" ] && [ -x /etc/init.d/ebrmain.sh ]; then
    if pidof ebrmain >/dev/null 2>&1 || pidof boordr >/dev/null 2>&1; then
        VIA_EBRMAIN="true"
        echo "[$(date)] koreader.sh: stopping the stock reader (KO_STOP_EBRMAIN set)" >>crash.log 2>&1
        /etc/init.d/ebrmain.sh stop >>crash.log 2>&1
    fi
fi

CRASH_COUNT=0
CRASH_TS=0
CRASH_PREV_TS=0
# 85 requests a KOReader restart; seed it so the loop runs once.
RETURN_VALUE=85

while [ ${RETURN_VALUE} -ne 0 ]; do
    if [ ${RETURN_VALUE} -eq 85 ]; then
        # Allow a restart to apply a pending Bookeen update.
        ko_update_check
    fi

    ./reader.lua "$@" >>crash.log 2>&1
    RETURN_VALUE=$?

    # Do not reopen a document that may have caused the crash.
    set --

    if [ ${RETURN_VALUE} -ne 0 ] && [ ${RETURN_VALUE} -ne 85 ]; then
        CRASH_COUNT=$((CRASH_COUNT + 1))
        CRASH_TS=$(date +'%s')
        # Start a new crash streak after a quiet interval.
        if [ $((CRASH_TS - CRASH_PREV_TS)) -ge 20 ]; then
            CRASH_COUNT=1
        fi

        if grep -q '\["dev_abort_on_crash"\] = true' 'settings.reader.lua' 2>/dev/null; then
            ALWAYS_ABORT="true"
            CRASH_COUNT=1
        else
            ALWAYS_ABORT="false"
        fi

        {
            echo "!!!!"
            echo "Uh oh, something went awry... (Crash n°${CRASH_COUNT} -> ${RETURN_VALUE}: $(date))"
            echo "Running on Linux $(uname -r) ($(uname -v))"
        } >>crash.log 2>&1

        if [ ${CRASH_COUNT} -ge 5 ]; then
            echo "Too many consecutive crashes, aborting . . ." >>crash.log 2>&1
            echo "!!!! ! !!!!" >>crash.log 2>&1
            # Show failure on the Bookeen panel instead of leaving stale content.
            ko_splash /system/update_finished_error.bmp
            break
        fi
        if [ "${ALWAYS_ABORT}" = "true" ]; then
            echo "Aborting on crash as requested . . ." >>crash.log 2>&1
            echo "!!!! ! !!!!" >>crash.log 2>&1
            ko_splash /system/update_finished_error.bmp
            break
        fi

        echo "Attempting to restart KOReader . . ." >>crash.log 2>&1
        echo "!!!!" >>crash.log 2>&1
        # Give the Bookeen device a short pause before retrying.
        if [ ${CRASH_COUNT} -eq 1 ]; then
            sleep 5
        fi
        CRASH_PREV_TS=${CRASH_TS}
    else
        CRASH_COUNT=0
    fi
done

if [ "${VIA_EBRMAIN}" = "true" ]; then
    echo "[$(date)] koreader.sh: restarting the stock reader" >>crash.log 2>&1
    /etc/init.d/ebrmain.sh start >>crash.log 2>&1
fi

exit ${RETURN_VALUE}
