#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

# print some useful info
echo "TRAVIS_BUILD_DIR: ${TRAVIS_BUILD_DIR}"
echo "pwd: $(pwd)"
ls

# toss submodules if there are any changes
# if [ "$(git status --ignore-submodules=dirty --porcelain)" ]; then
# "--ignore-submodules=dirty", removed temporarily, as it did not notice as
# expected that base was updated and kept using old cached base
if [ "$(git status --porcelain)" ]; then
    # what changed?
    git status
    # purge and reinit submodules
    git submodule deinit -f .
    git submodule update --init
else
    echo -e "${ANSI_GREEN}Using cached submodules."
fi

# install our own updated luarocks
if [ ! -f "${TRAVIS_BUILD_DIR}/install/bin/luarocks" ]; then
    git clone https://github.com/torch/luajit-rocks.git
    pushd luajit-rocks && {
        git checkout 6529891
        cmake . -DWITH_LUAJIT21=ON -DCMAKE_INSTALL_PREFIX="${TRAVIS_BUILD_DIR}/install"
        make install
    } || exit
    popd
else
    echo -e "${ANSI_GREEN}Using cached luarocks."
fi

if [ ! -d "${HOME}/.luarocks" ] || [ ! -f "${HOME}/.luarocks/$(md5sum <"${CI_DIR}/helper_luarocks.sh")" ]; then
    echo -e "${ANSI_GREEN}Grabbing new .luarocks."
    "${CI_DIR}/helper_luarocks.sh"
    touch "${HOME}/.luarocks/$(md5sum <"${CI_DIR}/helper_luarocks.sh")"
else
    echo -e "${ANSI_GREEN}Using cached .luarocks."
fi

#install our own updated shellcheck
SHELLCHECK_URL="https://s3.amazonaws.com/travis-blue-public/binaries/ubuntu/14.04/x86_64/shellcheck-0.4.5.tar.bz2"
if ! command -v shellcheck; then
    curl -sSL "${SHELLCHECK_URL}" | tar --exclude 'SHA256SUMS' --strip-components=1 -C "${HOME}/bin" -xjf -
    chmod +x "${HOME}/bin/shellcheck"
    shellcheck --version
else
    echo -e "${ANSI_GREEN}Using cached shellcheck."
fi

# install shfmt
SHFMT_URL="https://github.com/mvdan/sh/releases/download/v1.3.1/shfmt_v1.3.1_linux_amd64"
if [ "$(shfmt --version)" != "v1.3.1" ]; then
    curl -sSL "${SHFMT_URL}" -o "${HOME}/bin/shfmt"
    chmod +x "${HOME}/bin/shfmt"
else
    echo -e "${ANSI_GREEN}Using cached shfmt."
fi
