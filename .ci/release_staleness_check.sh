#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 0 ]] || die "no argument expected, got $#"

stale='true'

tag_name="$(git describe --tag --exact-match --match='v[0-9]*' 2>/dev/null)" || tag_name="${OTA_RELEASE}"
old_target="$(gh release view --json targetCommitish --template '{{ .targetCommitish }}' "${tag_name}" || true)"
new_target="$(git rev-parse HEAD)"

if [[ "${new_target}" == "${old_target}" ]]; then
    stale=
fi

# Debug.
{
    echo -e "${ANSI_GREEN}tag_name  : ${tag_name}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}old_target: ${old_target}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}new_target: ${new_target}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}stale     : ${stale}${ANSI_RESET}"
}

# Outputs.
printf '%s=%s\n' 'stale' "${stale}" >>"${GITHUB_OUTPUT}"

# vim: sw=4
