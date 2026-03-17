#!/bin/sh

export LC_ALL="en_US.UTF-8"

# Working directory.
KOREADER_DIR="$(dirname "$(realpath "$0")")"

# export @KOREADER_FLAVOR@

# FIXME: handle multiple arguments.
if [ $# -eq 1 ] && [ -e "$(pwd)/$1" ]; then
    ARGS="$(pwd)/$1"
else
    ARGS="$*"
fi

# We're always starting from our working directory.
cd "${KOREADER_DIR}" || exit

RETURN_VALUE=85
while [ ${RETURN_VALUE} -eq 85 ]; do
    ./reader.lua "${ARGS}"
    RETURN_VALUE=$?
    # Do not restart with saved arguments.
    ARGS="${HOME}"
done

exit ${RETURN_VALUE}
