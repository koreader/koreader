#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

pushd koreader-emulator-x86_64-linux-gnu/koreader && {
    circleci tests glob "spec/front/unit/*_spec.lua" | circleci tests split --split-by=timings --timings-type=filename | xargs -I{} sh -c 'make -C ../.. testfront BUSTED_SPEC_FILE="{}" || exit 255'
} && popd
#make testfront
