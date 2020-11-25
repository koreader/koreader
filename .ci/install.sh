#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

# print some useful info
echo "BUILD_DIR: ${CI_BUILD_DIR}"
echo "pwd: $(pwd)"
ls

# toss submodules if there are any changes
# if [ "$(git status --ignore-submodules=dirty --porcelain)" ]; then
# "--ignore-submodules=dirty", removed temporarily, as it did not notice as
# expected that base was updated and kept using old cached base
if [ "$(git status --ignore-submodules=dirty --porcelain)" ]; then
    # what changed?
    git status
    # purge and reinit submodules
    git submodule deinit -f .
    git submodule update --init
else
    echo -e "${ANSI_GREEN}Using cached submodules."
fi

# install our own updated luarocks
echo "luarocks installation path: ${CI_BUILD_DIR}"
if [ ! -f "${CI_BUILD_DIR}/install/bin/luarocks" ]; then
    git clone https://github.com/torch/luajit-rocks.git
    pushd luajit-rocks && {
        git checkout 6529891
        cmake . -DWITH_LUAJIT21=ON -DCMAKE_INSTALL_PREFIX="${CI_BUILD_DIR}/install"
        make install
    } && popd || exit
else
    echo -e "${ANSI_GREEN}Using cached luarocks."
fi

if [ ! -d "${HOME}/.luarocks" ] || [ ! -f "${HOME}/.luarocks/$(md5sum <"${CI_DIR}/helper_luarocks.sh")" ]; then
    echo -e "${ANSI_GREEN}Grabbing new .luarocks."
    sudo apt-get update
    # install openssl devel for luasec
    sudo apt-get -y install libssl-dev

    "${CI_DIR}/helper_luarocks.sh"
    touch "${HOME}/.luarocks/$(md5sum <"${CI_DIR}/helper_luarocks.sh")"
else
    echo -e "${ANSI_GREEN}Using cached .luarocks."
fi

#install our own updated shellcheck
SHELLCHECK_VERSION="v0.7.1"
SHELLCHECK_URL="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION?}/shellcheck-${SHELLCHECK_VERSION?}.linux.x86_64.tar.xz"
if ! command -v shellcheck; then
    curl -sSL "${SHELLCHECK_URL}" | tar --exclude 'SHA256SUMS' --strip-components=1 -C "${HOME}/bin" -xJf -
    chmod +x "${HOME}/bin/shellcheck"
    shellcheck --version
else
    echo -e "${ANSI_GREEN}Using cached shellcheck."
fi

# install shfmt
SHFMT_URL="https://github.com/mvdan/sh/releases/download/v3.2.0/shfmt_v3.2.0_linux_amd64"
if [ "$(shfmt --version)" != "v3.2.0" ]; then
    curl -sSL "${SHFMT_URL}" -o "${HOME}/bin/shfmt"
    chmod +x "${HOME}/bin/shfmt"
else
    echo -e "${ANSI_GREEN}Using cached shfmt."
fi
