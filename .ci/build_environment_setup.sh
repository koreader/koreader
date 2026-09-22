#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 1 ]] || die "1 arguments expected, got $#"
matrix_json="$1"
shift 1

# Convert matrix to associative array.
jq <<<"${matrix_json}"
out="$(jq --raw-output 'to_entries | map("[" + (.key | @sh) + "]=" + (.value | tostring | @sh)) | join(" ")' <<<"${matrix_json}")"
declare -A matrix="(${out})"

# Determine ccache directory.
CCACHE_DIR="$(ccache --get-config cache_dir)" || CCACHE_DIR="${PWD}/ccache"

# Job environment variables.
declare -a default_env=(
    CCACHE_DIR="${CCACHE_DIR}"
    CI="${CI}"
    CLICOLOR_FORCE=1
    GITHUB_ACTIONS="${GITHUB_ACTIONS}"
    INSTALL_DIR=install
    OUTPUT_DIR=build
    TARGET="${matrix[target]}"
)
if [[ "${matrix[target]}" == 'macos' ]]; then
    default_env+=(MACOSX_DEPLOYMENT_TARGET="${matrix[macosx_deployment_target]}")
fi
declare -a job_env="(${default_env[*]@Q} ${matrix[env]})"
# Export it now so things like `$CLICOLOR_FORCE` are available.
run export "${job_env[@]}"

# Setup GitHub environment.
run printf '%s\n' "${job_env[@]}" >>"${GITHUB_ENV}"

# Setup Docker.
if [[ -n "${matrix[image]}" ]]; then
    docker_opts=(
        "${job_env[@]/#/--env=}"
        --env="GRADLE_USER_HOME=${HOME}/.gradle"
        --volume="${HOME}:${HOME}"
        ${GITHUB_ACTIONS:+--volume=/github:/github}
    )
    if [[ -n "${matrix[platform]}" ]]; then
        docker_opts+=(--platform="${matrix[platform]}")
    fi
    run ./kodev docker create "${matrix[image]}" "${docker_opts[@]}"
    container_id="$(run docker container ls --latest --quiet)"
    run docker container rename "${container_id}" kontainer
fi

# Generate cache key.
run make TARGET= cache-key 2>&1
