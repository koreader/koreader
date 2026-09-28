#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

jq -L "${CI_DIR}" --raw-output --from-file "${CI_DIR}/assets_parse_to_sh.jq" --null-input --args "$@"
