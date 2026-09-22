#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 0 ]] || die "no arguments expected, got $#"

out="$(gh release view "${OTA_RELEASE}" --json 'assets' --template '{{ range .assets }}{{ .name }}{{ "\n" }}{{ end }}')"
readarray -t assets <<<"${out}"

printf '%bOTA assets:%b\n' "${ANSI_GREEN}" "${ANSI_RESET}"
printf '%s\n' "${assets[@]}"

# Trim assets:
# - keep the last stable
# - keep the last 3 nightlies more recent the latest stable
out="$("${CI_DIR}/assets_trim.sh" 1 3 "${assets[@]}")"
[[ -n "${out}" ]] && readarray -t assets <<<"${out}" || assets=()

# Delete trimmed assets.
for a in "${assets[@]}"; do
    run gh release delete-asset -y "${OTA_RELEASE}" "${a}"
done

# vim: sw=4
