#!/usr/bin/env bash

echo "Running koreader-emulator.sh"

# Locale setzen
export LC_ALL="en_US.UTF-8"

# Set path handling
if [ $# -eq 1 ] && [ -e "$(pwd)/${1}" ]; then
    ARGS="$(pwd)/${1}"
else
    ARGS="${*}"
fi

KOREADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${KOREADER_DIR}" || {
    echo "Error: emulator directory not found!"
    exit 1
}

CRASH_COUNT=0
CRASH_PREV_TS=0
KO_RC_RESTART=85
RETURN_VALUE=-1

while [ ${RETURN_VALUE} -ne 0 ]; do
    ./luajit reader.lua "${ARGS}" --crash-count=${CRASH_COUNT}
    RETURN_VALUE=$?

    # Check Exit or Restart
    if [ ${RETURN_VALUE} -eq 0 ] || [ ${RETURN_VALUE} -eq ${KO_RC_RESTART} ]; then
        if [ ${RETURN_VALUE} -eq 0 ]; then
            break # normal exit
        fi
        # If Restart (85), continue loop
        CRASH_COUNT=0
    else
        # That was a crash
        CRASH_COUNT=$((CRASH_COUNT + 1))
        CRASH_TS=$(date +'%s')

        # Reset if the last crash was too long ago
        if [ $((CRASH_TS - CRASH_PREV_TS)) -ge 20 ]; then
            CRASH_COUNT=1
        fi

        # Check User-Settings
        if grep -q '\["dev_abort_on_crash"\] = true' 'settings.reader.lua' 2>/dev/null; then
            ALWAYS_ABORT="true"
            CRASH_COUNT=1
        else
            ALWAYS_ABORT="false"
        fi

        # Log
        echo "--- last logs ---"
        tail -n 25 crash.log 2>/dev/null | sed -e 's/\t/    /g'
        echo "!!!! Crash n°${CRASH_COUNT} on $(date +'%x @ %X')"

        if [ ${CRASH_COUNT} -ge 5 ] || [ "${ALWAYS_ABORT}" = "true" ]; then
            echo "Exit: Too much crashes or 'dev_abort_on_crash'."
            break
        fi

        CRASH_PREV_TS=${CRASH_TS}
        echo "Try reastart in 2 seconds"
        sleep 2
    fi
done

exit ${RETURN_VALUE}
