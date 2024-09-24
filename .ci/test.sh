#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

pushd install/koreader && {
    # the circleci command spits out newlines; we want spaces instead
    BUSTED_OVERRIDES="$(circleci tests glob "spec/front/unit/*_spec.lua" | circleci tests split --split-by=timings --timings-type=filename | tr '\n' ' ')"
} && popd || exit

make testfront --assume-old=all BUSTED_OVERRIDES="${BUSTED_OVERRIDES}"

# vim: sw=4
