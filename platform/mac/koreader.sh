#!/bin/bash
export LC_ALL="en_US.UTF-8"

export KO_MULTIUSER=1
USER_STORAGE="${HOME}/.config/koreader"
[ ! -d "${USER_STORAGE}" ] && mkdir -p "${USER_STORAGE}"

# working directory of koreader
KOREADER_DIR="${0%/*}/../koreader"

# arguments
if [ -z "${1}" ]; then
    ARGS=${HOME}
else
    ARGS=${*}
fi

# we're always starting from our working directory
cd "${KOREADER_DIR}" || exit
RETURN_VALUE=85
while [ ${RETURN_VALUE} -eq 85 ]; do
    ./reader.lua "${ARGS}"
    RETURN_VALUE=$?
    ARGS=${HOME}
done

# remove the flag to avoid emulator confusion
export -n KO_MULTIUSER

exit ${RETURN_VALUE}
