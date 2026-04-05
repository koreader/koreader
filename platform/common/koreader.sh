#!/bin/sh

export LC_ALL="en_US.UTF-8"

# Working directory.
KOREADER_DIR="$(dirname "$(realpath "$0")")"

# export @KOREADER_FLAVOR@

# Canonicalize non-option arguments so we can change dir.
# (Pop left, push right - each arg once so we end with the orig order.)
for arg; do
    shift
    if [ -e "${PWD}/${arg}" ]; then
        arg="${PWD}/${arg}"
    fi
    set -- "$@" "${arg}"
done

# We're always starting from our working directory.
cd "${KOREADER_DIR}" || exit

RETURN_VALUE=85
while [ ${RETURN_VALUE} -eq 85 ]; do
    ./reader.lua "$@"
    RETURN_VALUE=$?
    # Do not restart with saved arguments.
    set -- "${HOME}"
done

exit ${RETURN_VALUE}
