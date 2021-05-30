#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

rm -rf "${HOME}/.luarocks"
mkdir "${HOME}/.luarocks"
cp "${CI_BUILD_DIR}/install/etc/luarocks/config.lua" "${HOME}/.luarocks/config.lua"
echo "wrap_bin_scripts = false" >>"${HOME}/.luarocks/config.lua"
travis_retry luarocks --local install luafilesystem
# for verbose_print module
travis_retry luarocks --local install ansicolors
travis_retry luarocks --local install busted sc-1

travis_retry luarocks --local install luacheck
travis_retry luarocks --local install lanes # for parallel luacheck

# used only on master branch but added to cache for better speed
travis_retry luarocks --local install ldoc
travis_retry luarocks --local install luacov
