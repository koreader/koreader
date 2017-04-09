#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

# print some useful info
echo "TRAVIS_BUILD_DIR: ${TRAVIS_BUILD_DIR}"
echo "pwd: $(pwd)"
ls

# toss submodules if there are any changes
if [ "$(git status --ignore-submodules=dirty --porcelain)" ]; then
    # what changed?
    git status
    # purge and reinit submodules
    git submodule deinit -f .
    git submodule update --init
else
    echo "Using cached submodules."
fi

# install our own updated luarocks
if [ ! -f "${TRAVIS_BUILD_DIR}/install/bin/luarocks" ]; then
    git clone https://github.com/torch/luajit-rocks.git
    pushd luajit-rocks
        git checkout 6529891
        cmake . -DWITH_LUAJIT21=ON -DCMAKE_INSTALL_PREFIX="${TRAVIS_BUILD_DIR}/install"
        make install
    popd
else
    echo "Using cached luarocks."
fi

if [ ! -d "${HOME}/.luarocks" ]; then
    mkdir "${HOME}/.luarocks"
    cp "${TRAVIS_BUILD_DIR}/install/etc/luarocks/config.lua" "${HOME}/.luarocks/config.lua"
    echo "wrap_bin_scripts = false" >> "$HOME/.luarocks/config.lua"
    travis_retry luarocks --local install luafilesystem
    # for verbose_print module
    travis_retry luarocks --local install ansicolors
    travis_retry luarocks --local install busted 2.0.rc12-1
    #- mv -f $HOME/.luarocks/bin/busted_bootstrap $HOME/.luarocks/bin/busted
    travis_retry luarocks --local install luacov
    # luasec doesn't automatically detect 64-bit libs
    travis_retry luarocks --local install luasec OPENSSL_LIBDIR=/usr/lib/x86_64-linux-gnu
    travis_retry luarocks --local install luacov-coveralls --server=http://rocks.moonscript.org/dev
    travis_retry luarocks --local install luacheck
    travis_retry luarocks --local install lanes  # for parallel luacheck
else
    echo "Using cached .luarocks."
fi

#install our own updated shellcheck
SHELLCHECK_URL="https://s3.amazonaws.com/travis-blue-public/binaries/ubuntu/14.04/x86_64/shellcheck-0.4.5.tar.bz2"
if ! command -v shellcheck ; then
    curl -sSL "${SHELLCHECK_URL}" | tar --exclude 'SHA256SUMS' --strip-components=1 -C "${HOME}/bin" -xjf -;
    chmod +x "${HOME}/bin/shellcheck"
    shellcheck --version
else
    echo "Using cached shellcheck."
fi

# install shfmt
SHFMT_URL="https://github.com/mvdan/sh/releases/download/v1.2.0/shfmt_v1.2.0_linux_amd64"
if ! command -v shfmt ; then
    curl -sSL "${SHFMT_URL}" -o "${HOME}/bin/shfmt"
    chmod +x "${HOME}/bin/shfmt"
else
    echo "Using cached shfmt."
fi
