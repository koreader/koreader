#!/bin/bash

INSTALL_DIR="$1"
JNILIBS_DIR="$2"
SYMBOLIC_MAP="$3"

# avoid duplicates
function checkAndCopy() {
    if [ ! -f "${JNILIBS_DIR}/${2}" ]; then
        src="${INSTALL_DIR}/${1}"
        dest="${JNILIBS_DIR}/${2}"
        cp -pv "${src}" "${dest}"
        echo "${1} ${2}" >> "${SYMBOLIC_MAP}"
    fi
}

mapfile -t array < <(cd "${INSTALL_DIR}" && find libs/ plugins/ -type f -name '*.so')
for i in "${array[@]}"; do
    file="${i##*/}"
    checkAndCopy "${i}" "${file}"
done

