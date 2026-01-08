#!/usr/bin/env bash

# env-variables:
# KOREADER_EMULATE    if set, use '~/koreader/' to store data
#

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${KOREADER_EMULATE}" ]; then
    ## OK, we are on linux target
    cd "${SOURCE_DIR}/../lib/koreader" || exit 1
    # Writable storage in the home directory
    KO_MULTIUSER=1
fi

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
    local CALL_ARGS="$1"
    local CRASH_COUNT=0
    local CRASH_PREV_TS=0
    local KO_RC_RESTART=85
    local RETURN_VALUE=-1

    while [ ${RETURN_VALUE} -ne 0 ]; do
        env ${KO_MULTIUSER:+KO_MULTIUSER=${KO_MULTIUSER}} CRASH_COUNT=${CRASH_COUNT} ./reader.lua "${CALL_ARGS}"
        RETURN_VALUE=$?

        # Restart (85) or clean exit (0)
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

ARGS=$(setup_args "$@")
cd "${SOURCE_DIR}" || exit 1

run_koreader_loop "${ARGS}"
exit $?
