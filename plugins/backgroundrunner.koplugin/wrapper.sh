#!/bin/sh

# Starts the arguments as a bash command in background with low priority. The
# command will be killed if it executes for over 1 hour. If the command failed
# to start, this script returns 127. If the command is timed out, this script
# returns 255. Otherwise the return value of the command will be returned.

echo "TIMEOUT in environment: ${TIMEOUT}"

if [ -z "${TIMEOUT}" ]; then
    TIMEOUT=3600
fi

echo "Timeout has been set to ${TIMEOUT} seconds"

echo "Will start command $*"

echo "$@" | nice -n 19 sh &
JOB_ID=$!
echo "Job id: ${JOB_ID}"

for i in $(seq 1 1 "${TIMEOUT}"); do
    if ps -p "${JOB_ID}" >/dev/null 2>&1; then
        # Job is still running.
        sleep 1
        ROUND=$(printf "%s" "${i}" | tail -c 1)
        if [ "${ROUND}" -eq "0" ]; then
            echo "Job ${JOB_ID} is still running ... waited for ${i} seconds."
        fi
    else
        wait ${JOB_ID}
        exit $?
    fi
done

echo "Command $* has timed out"

kill -9 ${JOB_ID}
exit 255
