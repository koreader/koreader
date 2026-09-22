#!/usr/bin/env bash

set -e
set -o pipefail

declare -r ANSI_DIM=$'\033[2m'
declare -r ANSI_RED=$'\033[31;1m'
declare -r ANSI_GREEN=$'\033[32;1m'
declare -r ANSI_BLUE=$'\033[34;1m'
declare -r ANSI_RESET=$'\033[0m'

# shellcheck disable=SC2034
declare -r OTA_RELEASE='ota'

DRY_RUN="${DRY_RUN:-}"

quote() {
    [[ $# -ge 0 ]] || return 0
    printf '%q' "$1"
    shift
    [[ $# -eq 0 ]] || printf ' %q' "$@"
    printf '\n'
}

err() {
    printf '%s\n' "${ANSI_RED}$*${ANSI_RESET}" 1>&2
}

die() {
    err "$@"
    exit 1
}

run() {
    local code pipe
    if [[ "$1" == '|' ]]; then
        pipe='1'
        shift
    fi
    printf '%s\n' "${GITHUB_ACTIONS:+::group::}${ANSI_BLUE}${pipe:+| }$(quote "$@")${ANSI_RESET}" 1>&2
    if [[ -n "${DRY_RUN}" ]]; then
        code=0
    else
        "$@" && code=0 || code=$?
    fi
    if [[ "${code}" != 0 ]]; then
        err "Error: exit code ${code}"
    fi
    [[ -z "${GITHUB_ACTIONS}" ]] || printf '::endgroup::\n' 1>&2
    return "${code}"
}

ONEXIT=()

onexit() {
    ONEXIT+=("$@")
    local handler
    handler="true$(printf " && %s" "${ONEXIT[@]}")"
    printf '%s\n' "${ANSI_DIM}trap ${handler@Q} EXIT${ANSI_RESET}"
    # shellcheck disable=SC2064
    trap "printf '%s\n' '${ANSI_DIM}EXIT trap${ANSI_RESET}'; ${handler}" EXIT
}

# Docker helpers. {{{

declare -r CONTAINER_IMAGE='koreader/nightswatcher:1.7.1'

container_start() {
    CONTAINER_ID="$(run docker run --detach --tty --volume="${PWD}:/work" --workdir=/work "${CONTAINER_IMAGE}" sh -c 'while true; do sleep 0.25; done')"
    # shellcheck disable=SC2016
    onexit 'run docker kill "${CONTAINER_ID}" && run docker rm "${CONTAINER_ID}"'
}

container_exec() {
    local code
    printf '%s\n' "${GITHUB_ACTIONS:+::group::}${ANSI_BLUE}$(quote "$@")${ANSI_RESET}${ANSI_DIM} [docker]${ANSI_RESET}" 1>&2
    if [[ -n "${DRY_RUN}" ]]; then
        code=0
    else
        docker exec --tty "${CONTAINER_ID}" "$@" && code=0 || code=$?
    fi
    if [[ "${code}" != 0 ]]; then
        err "Error: exit code ${code}"
    fi
    [[ -z "${GITHUB_ACTIONS}" ]] || printf '::endgroup::\n' 1>&2
    return "${code}" 1>&2
}

# }}}

# Ensure `$GITHUB_ENV` and the like are set (fallback to stdout).
: "${GITHUB_ENV:=/proc/self/fd/1} ${GITHUB_OUTPUT:=/proc/self/fd/1} ${GITHUB_PATH:=/proc/self/fd/1}"

printf '%s\n' "${ANSI_GREEN}$(quote "$0" "$@")${ANSI_RESET}" 1>&2
trap 'err "Error: exit code $?"' ERR
