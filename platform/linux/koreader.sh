#!/usr/bin/env bash
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export LC_ALL="en_US.UTF-8"

setup_args() {
    if [ $# -eq 1 ] && [ -e "$(pwd)/${1}" ]; then
        echo "$(pwd)/${1}"
    else
        echo "${*}"
    fi
}

# main loop for emulator and linux
run_koreader_loop() {
    local ARGS="$1"
    local CRASH_COUNT=0
    local CRASH_PREV_TS=0
    local KO_RC_RESTART=85
    local RETURN_VALUE=-1

    while [ ${RETURN_VALUE} -ne 0 ]; do
        CRASH_COUNT=${CRASH_COUNT} ./reader.lua "${ARGS}"
        RETURN_VALUE=$?

        # Falls Neustart (85) oder sauberer Exit (0)
        if [ ${RETURN_VALUE} -eq 0 ] || [ ${RETURN_VALUE} -eq ${KO_RC_RESTART} ]; then
            [ ${RETURN_VALUE} -eq 0 ] && break
            CRASH_COUNT=0
        else
            # Crash-Handling
            local CRASH_TS
            CRASH_TS=$(date +'%s')

            CRASH_COUNT=$((CRASH_COUNT + 1))

            [ $((CRASH_TS - CRASH_PREV_TS)) -ge 20 ] && CRASH_COUNT=1

            if grep -q '\["dev_abort_on_crash"\] = true' 'settings.reader.lua' 2>/dev/null; then
                echo "Exit: 'dev_abort_on_crash' is true."
                break
            fi

            echo "--- last logs ---"
            tail -n 25 crash.log 2>/dev/null | sed -e 's/\t/    /g'
            echo "!!!! Crash n°${CRASH_COUNT} on $(date +'%x @ %X')"

            if [ ${CRASH_COUNT} -ge 5 ]; then
                echo "Exit: Too many crashes."
                break
            fi

            CRASH_PREV_TS=${CRASH_TS}
            echo "Try restart in 2 seconds"
            sleep 2
        fi
    done
    return ${RETURN_VALUE}
}

# Writable storage
export KO_MULTIUSER=1

ARGS=$(setup_args "$@")
cd "${SOURCE_DIR}/../lib/koreader" || exit 1

run_koreader_loop "${ARGS}"
RET=$?

export -n KO_MULTIUSER
exit ${RET}
