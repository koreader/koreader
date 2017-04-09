#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

travis_retry make fetchthirdparty
find . -type f -name '*.sh' -not -path "./base/*" -not -path "./luajit-rocks/*" -print0 | xargs --null shellcheck
find . -type f -name '*.sh' -not -path "./base/*" -not -path "./luajit-rocks/*" -print0 | xargs --null shfmt -i 0 -w
lua "$(which luacheck)" --no-color -q {reader,setupkoenv,datastorage}.lua frontend plugins
make all
make testfront
