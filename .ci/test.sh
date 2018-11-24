#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

pushd koreader-emulator-x86_64-linux-gnu/koreader && {
    # the circleci command spits out newlines; we want spaces instead
    BUSTED_SPEC_FILE="$(circleci tests glob "spec/front/unit/*_spec.lua" | circleci tests split --split-by=timings --timings-type=filename | tr '\n' ' ')"
} && popd || exit

# symlink to prevent trouble finding the lib on Ubuntu 16.04 in the Docker image
ln -sf /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0 koreader-emulator-x86_64-linux-gnu/koreader/libs/libSDL2.so

make testfront BUSTED_SPEC_FILE="${BUSTED_SPEC_FILE}"
