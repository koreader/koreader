#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -ge 3 ]] || die "at least 3 arguments expected, got $#"
stable_keep_count="$1"
nightly_keep_count="$2"
shift 2

jq -L "${CI_DIR}" --raw-output --from-file "${CI_DIR}/assets_trim.jq" --null-input --argjson stable_keep_count "${stable_keep_count}" --argjson nightly_keep_count "${nightly_keep_count}" --args "$@"
