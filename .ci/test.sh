#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

pushd install/koreader && {
    # the circleci command spits out newlines; we want spaces instead
    BUSTED_SPEC_FILE="$(circleci tests glob "spec/front/unit/*_spec.lua" | circleci tests split --split-by=timings --timings-type=filename | tr '\n' ' ')"
} && popd || exit

make testfront BUSTED_SPEC_FILE="${BUSTED_SPEC_FILE}"

# vim: sw=4
