#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 2 ]] || [[ $# -eq 3 ]] || die "2 or 3 arguments expected, got $#"
inputs="$1"
shift 1

# Compact inputs (and validate it's JSON).
inputs="$(jq --compact-output --sort-keys . <<<"${inputs}")"

# Generate build cache key.
mkdir -p base
readarray -t cache_key_build_paths <"${CI_DIR}/build_cache_key_paths.txt"
cache_key_build_manifest="$(run git -C base ls-files -z "${cache_key_build_paths[@]}" | run '|' xargs -0 git -C base ls-tree @)"
cache_key_build="$(sha256sum <<<"${cache_key_build_manifest}" | cut -d\  -f1)"
printf '%s\n' "${GITHUB_ACTIONS:+::group::}${ANSI_GREEN}build cache key:${ANSI_RESET} ${cache_key_build}" "${cache_key_build_manifest}" "${GITHUB_ACTIONS:+::endgroup::}"

# Fetch matching caches.
cache_epoch="$(jq --raw-output .cache_epoch <<<"${inputs}")"
caches=
for ref in "$@"; do
    [[ -n "${ref}" ]] || continue
    caches+="$(run gh api -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2026-03-10' "/repos/{owner}/{repo}/actions/caches?per_page=100&key=${cache_epoch}-build&ref=${ref}")"
done
caches="$(run jq --compact-output --slurp '[.[] | .actions_caches] | flatten | unique' <<<"${caches}")"
printf '%s\n' "${caches}" >'caches.json'
printf '%s\n' "${GITHUB_ACTIONS:+::group::}${ANSI_GREEN}caches:${ANSI_RESET} $(jq length caches.json)"
jq --color-output . caches.json
printf '%s\n' "${GITHUB_ACTIONS:+::endgroup::}"

# We'll need to expand the build jobs YAML to JSON.
yq=("$( (which yq4 || which yq) 2>/dev/null)")
if "${yq[@]}" --yaml-fix-merge-anchor-to-spec >/dev/null 2>&1; then
    yq+=(--yaml-fix-merge-anchor-to-spec)
fi

# Generate jobs matrix.
jobs="$(run "${yq[@]}" --output-format=json . "${CI_DIR}/build_jobs.yml" | run '|' jq --compact-output --from-file "${CI_DIR}/build_matrix_generate.jq" --arg cache_key_build "${cache_key_build}" --slurpfile caches caches.json --argjson inputs "${inputs}")"

# Debug.
{
    printf '%s\n' "${ANSI_GREEN}jobs:${ANSI_RESET} "
    <<<"${jobs}" jq --color-output --sort-keys
    printf '%s\n' "${ANSI_GREEN}jobs (expanded):${ANSI_RESET} "
    <<<"${jobs}" jq --color-output --sort-keys 'to_entries | map(.value = (.value | fromjson)) | from_entries'
}

# Outputs.
printf '%s=%s\n' 'jobs' "${jobs}" >>"${GITHUB_OUTPUT}"

# vim: sw=4
