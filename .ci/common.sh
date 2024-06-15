#!/usr/bin/env bash

set -e
set -o pipefail

ANSI_RED="\033[31;1m"
# shellcheck disable=SC2034
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"

travis_retry() {
    local result=0
    local count=1
    set +e

    while [ ${count} -le 3 ]; do
        [ ${result} -ne 0 ] && {
            echo -e "\n${ANSI_RED}The command \"$*\" failed. Retrying, ${count} of 3.${ANSI_RESET}\n" >&2
        }
        "$@"
        result=$?
        [ ${result} -eq 0 ] && break
        count=$((count + 1))
        sleep 1
    done

    [ ${count} -gt 3 ] && {
        echo -e "\n${ANSI_RED}The command \"$*\" failed 3 times.${ANSI_RESET}\n" >&2
    }

    set -e
    return ${result}
}
