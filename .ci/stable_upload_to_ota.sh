#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 2 ]] || die "2 arguments expected, got $#"
assets_dir="$1"
release_tag="$2"
shift 1

# Download release assets.
run gh release download --dir="${assets_dir}" "${release_tag}"

# Generate OTA assets.
run "${CI_DIR}/ota_assets_generate.sh" stable "${assets_dir}"

# Label assets.
out="$("${CI_DIR}/assets_filter_label_and_sort.sh" nightly "${assets_dir}"/*)"
readarray -t assets <<<"${out}"

# Upload them to the OTA release.
run gh release upload --clobber "${OTA_RELEASE}" "${assets[@]}"

# And trim old versions.
run "${CI_DIR}/ota_release_trim.sh"
