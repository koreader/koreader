#!/usr/bin/env bash

set -e
set -o pipefail

ANSI_RED="\033[31;1m"
# shellcheck disable=SC2034
ANSI_GREEN="\033[32;1m"
ANSI_RESET="\033[0m"
# shellcheck disable=SC2034
ANSI_CLEAR="\033[0K"

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

retry_cmd() {
    local result=0
    local count=1
    set +e

    retry_cnt=$1
    shift 1

    while [ ${count} -le "${retry_cnt}" ]; do
        [ ${result} -ne 0 ] && {
            echo -e "\n${ANSI_RED}The command \"$*\" failed. Retrying, ${count} of ${retry_cnt}${ANSI_RESET}\n" >&2
        }
        "$@"
        result=$?
        [ ${result} -eq 0 ] && break
        count=$((count + 1))
        sleep 1
    done

    [ ${count} -gt "${retry_cnt}" ] && {
        echo -e "\n${ANSI_RED}The command \"$*\" failed ${retry_cnt} times.${ANSI_RESET}\n" >&2
    }

    set -e
    return ${result}
}

# export CI_BUILD_DIR=${TRAVIS_BUILD_DIR}
# use eval to get fully expanded path
eval CI_BUILD_DIR="${CIRCLE_WORKING_DIRECTORY}"
export CI_BUILD_DIR

test -e "${HOME}/bin" || mkdir "${HOME}/bin"
export PATH=${PWD}/bin:${HOME}/bin:${PATH}
export PATH=${PATH}:${CI_BUILD_DIR}/install/bin
if [ -f "${CI_BUILD_DIR}/install/bin/luarocks" ]; then
    # add local rocks to $PATH
    eval "$(luarocks path --bin)"
fi
