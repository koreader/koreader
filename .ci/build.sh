#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

# Build.
cmd=(make all)
if [[ -d build ]]; then
    cmd+=(--assume-old=base)
fi
"${cmd[@]}"

# vim: sw=4
