#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 1 ]] || die "1 argument expected, got $#"
assets_dir="$1"
shift

if tag_name="$(git describe --tag --exact-match --match='v[0-9]*' 2>/dev/null)"; then
    channel='stable'
    draft=1
    prerelease=
    title="${tag_name}"
else
    tag_name="${OTA_RELEASE}"
    channel='nightly'
    draft=
    prerelease=1
    title='OTA'
fi

target="$(git rev-parse HEAD)"

if out="$(gh release view "${tag_name}" --json 'assets' --template '{{ range .assets }}{{ .name }}{{ "\n" }}{{ end }}')"; then
    readarray -t old_assets <<<"${out}"
    mode='edit'
else
    old_assets=()
    mode='create'
fi

{
    echo -e "${ANSI_GREEN}tag_name  : ${tag_name}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}channel   : ${channel}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}mode      : ${mode}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}draft     : ${draft:-0}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}prerelease: ${prerelease:-0}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}title     : ${title}${ANSI_RESET}"
    echo -e "${ANSI_GREEN}target    : ${target}${ANSI_RESET}"
} 1>&2

if [[ "${channel}" == 'nightly' ]]; then
    # Generate OTA assets.
    run "${CI_DIR}/ota_assets_generate.sh" "${channel}" "${assets_dir}"
fi

# Label assets.
out="$("${CI_DIR}/assets_filter_label_and_sort.sh" "${channel}" "${assets_dir}"/*)"
readarray -t assets <<<"${out}"

# Create / update release.
cmd=(gh release "${mode}" --target="${target}")
if [[ "${mode}" == 'create' ]]; then
    cmd+=(${draft:+--draft} ${prerelease:+--prerelease} --title="${title}" --notes='')
fi
cmd+=("${tag_name}")
run "${cmd[@]}"

# Upload assets.
run gh release upload --clobber "${tag_name}" "${assets[@]}"

# Update OTA tag.
if [[ "${channel}" == 'nightly' ]]; then
    run git push -f origin "${target}:refs/tags/${tag_name}"
fi

# Cleanup:
if [[ "${channel}" == 'nightly' ]]; then
    # - nightly: old versions
    run "${CI_DIR}/ota_release_trim.sh"
else
    # - stable: left-overs from previous version
    out="$(comm -23 <(printf '%s\n' "${old_assets[@]}" | sort) <(printf '%s\n' "${assets[@]}" | sed 's,^.*/,,;s,#.*$,,;' | sort))"
    if [[ -n "${out}" ]]; then
        readarray -t old_assets <<<"${out}"
        for a in "${old_assets[@]}"; do
            run gh release delete-asset -y "${tag_name}" "${a}"
        done
    fi
fi

# vim: sw=4
