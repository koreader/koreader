#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

echo -e "\n${ANSI_GREEN}make fetchthirdparty"
travis_retry make fetchthirdparty

"${CI_DIR}/helper_shellchecks.sh"

echo -e "\n${ANSI_GREEN}Luacheck results"
luajit "$(which luacheck)" --no-color -q {reader,setupkoenv,datastorage}.lua frontend plugins spec

echo -e "\n${ANSI_GREEN}make all"
make all

luarocks --local install lua-curl #to hopefully get more info out of luacov-coveralls

travis_retry make coverage
pushd koreader-*/koreader && {
    luajit "$(which luacov-coveralls)" --verbose
} || exit
popd

echo -e "\n${ANSI_GREEN}make testfront"
make testfront
