#!/bin/sh

export LC_ALL="en_US.UTF-8"

# Working directory.
KOREADER_DIR="$(dirname "$(realpath "$0")")"

# export @KOREADER_FLAVOR@

unset _args_cleared
for arg; do
    # clear positional args in the first iteration so we can append afterwards
    if [ -z "${_args_cleared}" ]; then
        set --
        _args_cleared=:
    fi

    if [ -e "${PWD}/${arg}" ]; then
        set -- "$@" "${PWD}/${arg}"
    else
        set -- "$@" "${arg}"
    fi
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
