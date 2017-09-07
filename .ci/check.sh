#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

echo -e "\n${ANSI_GREEN}shellcheck results"
"${CI_DIR}/helper_shellchecks.sh"

echo -e "\n${ANSI_GREEN}Luacheck results"
luajit "$(which luacheck)" --no-color -q {reader,setupkoenv,datastorage}.lua frontend plugins spec
