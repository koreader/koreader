#!/usr/bin/env bash
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SOURCE_DIR}/linux-common.sh"

ARGS=$(setup_args "$@")
cd "${SOURCE_DIR}" || exit 1

run_koreader_loop "${ARGS}"
exit $?