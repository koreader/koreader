#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

echo -e "\n${ANSI_GREEN}make fetchthirdparty"
travis_retry make fetchthirdparty

# shellcheck source=/dev/null
."${CI_DIR}/helper_shellchecks.sh"

echo -e "\n${ANSI_GREEN}Luacheck results"
luajit "$(which luacheck)" --no-color -q {reader,setupkoenv,datastorage}.lua frontend plugins

echo -e "\n${ANSI_GREEN}make all"
make all
echo -e "\n${ANSI_GREEN}make testfront"
make testfront
