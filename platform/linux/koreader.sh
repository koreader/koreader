#!/usr/bin/env bash
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/linux-common.sh"

# Writable storage setzen
export KO_MULTIUSER=1

ARGS=$(setup_args "$@")
# Spezifisches Verzeichnis für koreader.sh
cd "${SOURCE_DIR}/../lib/koreader" || exit 1

run_koreader_loop "${ARGS}"
RET=$?

export -n KO_MULTIUSER
exit ${RET}