#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CI_DIR}/common.sh"

travis_retry make fetchthirdparty
make all
make testfront
luajit $(which luacheck) --no-color -q frontend
