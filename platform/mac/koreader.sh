#!/bin/bash
export LC_ALL="en_US.UTF-8"

# writable storage: ${HOME}/.config/koreader.
export KO_MULTIUSER=1

# working directory of koreader
KOREADER_DIR="${0%/*}/../Resources/koreader"

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit
RETURN_VALUE=85
while [ ${RETURN_VALUE} -eq 85 ]; do
    ./reader.lua "${ARGS}"
    RETURN_VALUE=$?
done

# remove the flag to avoid emulator confusion
export -n KO_MULTIUSER

exit ${RETURN_VALUE}
