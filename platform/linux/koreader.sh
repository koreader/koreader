#!/usr/bin/env bash
export LC_ALL="en_US.UTF-8"

# writable storage: ${HOME}/.config/koreader.
export KO_MULTIUSER=1

if [ $# -eq 1 ] && [ -e "$(pwd)/${1}" ]; then
    ARGS="$(pwd)/${1}"
else
    ARGS="${*}"
fi

# working directory of koreader
KOREADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/koreader"

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit

RETURN_VALUE=85
while [ ${RETURN_VALUE} -eq 85 ]; do
    ./reader.lua "${ARGS}"
    RETURN_VALUE=$?
    # do not restart with saved arguments
    ARGS="${HOME}"
done

# remove the flag to avoid emulator confusion
export -n KO_MULTIUSER

exit ${RETURN_VALUE}
