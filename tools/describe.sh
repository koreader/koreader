#!/usr/bin/env bash

set -eo pipefail

if [[ -n "${CLIFORCE_COLOR}" ]] || [[ -t 2 ]]; then
    declare -r ANSI_MAGENTA=$'\033[35;1m'
    declare -r ANSI_RESET=$'\033[0m'
else
    declare -r ANSI_MAGENTA=''
    declare -r ANSI_RESET=''
fi

export TZ=UTC

release_date="$(git show -s --format=format:"%cd" --date=short HEAD)"

if out="$(git describe --match='v[0-9]*' HEAD 2>&1)"; then
    version="${out}"
    epoch_rev="${version%%-*}"
else
    # No tag, shallow clone?
    printf '%s\n' "${ANSI_MAGENTA}WARNING: cannot describe current git revision:${ANSI_RESET} ${out}" 1>&2
    version="v0000.00-0-g$(git rev-parse --short=10 @)"
    epoch_rev='@'
fi
# Only append date if we're not on a whole version, like v2018.11.
case "${version}" in *-*) version="${version}_${release_date}" ;; esac

release_epoch="$(git log -1 --format='%cs' "${epoch_rev}")"

printf '%s\n' "${version}" "${release_date}" "${release_epoch}"
