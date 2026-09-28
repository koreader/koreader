#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -ge 2 ]] || die "at least 2 arguments expected, got $#"
channel="$1"
shift

jq -L "${CI_DIR}" --raw-output --from-file "${CI_DIR}/assets_filter_label_and_sort.jq" --null-input --arg channel "${channel}" --args "$@"
