#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CI_DIR}/common.sh"

# install our own updated luarocks
git clone https://github.com/torch/luajit-rocks.git
pushd luajit-rocks
    git checkout 6529891
    cmake . -DWITH_LUAJIT21=ON -DCMAKE_INSTALL_PREFIX=${TRAVIS_BUILD_DIR}/install
    make install
popd

mkdir $HOME/.luarocks
cp ${TRAVIS_BUILD_DIR}/install/etc/luarocks/config.lua $HOME/.luarocks/config.lua
echo "wrap_bin_scripts = false" >> $HOME/.luarocks/config.lua
travis_retry luarocks --local install luafilesystem
travis_retry luarocks --local install ansicolors
travis_retry luarocks --local install busted 2.0.rc11-0
#- travis_retry luarocks --local install busted 1.11.1-1
#- mv -f $HOME/.luarocks/bin/busted_bootstrap $HOME/.luarocks/bin/busted
travis_retry luarocks --local install luacov
# luasec doesn't automatically detect 64-bit libs
travis_retry luarocks --local install luasec OPENSSL_LIBDIR=/usr/lib/x86_64-linux-gnu
travis_retry luarocks --local install luacov-coveralls --server=http://rocks.moonscript.org/dev
travis_retry luarocks --local install luacheck
travis_retry luarocks --local install lanes  # for parallel luacheck
travis_retry luarocks --local install ldoc
