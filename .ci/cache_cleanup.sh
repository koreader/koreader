#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 1 ]] || die "1 argument expected, got $#"
branch="$1"
shift

out="$(gh cache list --ref "${branch}" --limit 100 --json key --jq '.[].key')"
[[ -n "${out}" ]] || exit 0
readarray -t keylist <<<"${out}"

for key in "${keylist[@]}"; do
    run gh cache delete --ref "${branch}" "${key}" || true
done

# vim: sw=4
