#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 1 ]] || die "1 argument expected, got $#"
assets_dir="$1"
shift

apks_sign() {
    local cmd=(
        uber-apk-signer
        --ks "${APK_SIGN_TEMP_STORE}"
        --ksAlias "${APK_SIGN_KEY_ALIAS}"
        --ksKeyPass "${APK_SIGN_KEY_PASS}"
        --ksPass "${APK_SIGN_STORE_PASS}"
        --allowResign
        --overwrite
        --verbose
        --apks
    )
    container_exec "${cmd[@]}" "$@"
    # We don't use those (detached signatures for supporting ADB streamed installs).
    run rm -f "${@/%/.idsig}"
}

# Setup temporary store.
APK_SIGN_TEMP_STORE="$(mktemp --tmpdir=. -t apk_sign_store.XXXXXXXXXX)"
# shellcheck disable=SC2016
onexit 'rm -f "${APK_SIGN_TEMP_STORE}"'
base64 -d >"${APK_SIGN_TEMP_STORE}" <<<"${APK_SIGN_STORE_BASE64}"

# Start helper container.
container_start

# Sign APKs.
for a in "${assets_dir}"/koreader-*.apk; do
    [[ -e "${a}" ]] || continue
    apks_sign "${a}"
done

# vim: sw=4
