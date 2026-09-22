#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

[[ $# -eq 2 ]] || die "2 arguments expected, got $#"
channel="$1"
assets_dir="$(realpath "$2")"
shift 2

procs="$(getconf _NPROCESSORS_ONLN)"

latest_make() {
    [[ $# -eq 4 ]] || return
    local mode="$1" file="$2" latest="$3" latest_nightly="$4"
    case "${mode}" in
        copy) run cp "${file}" "${latest}" ;;
        link) run sh -c "echo $(quote "${file}") >$(quote "${latest}")" ;;
        *) return 1 ;;
    esac
    if [[ "${latest}" != "${latest_nightly}" ]]; then
        run cp "${latest}" "${latest_nightly}"
    fi
}

release_make() {
    container_exec ./.mkrelease.sh --jobs "${procs}" "$@"
}

kotasync_make() {
    [[ $# -eq 4 ]] || return
    local txz="$1" kotasync="$2" latest="$3" latest_nightly="$4"
    local cmd=(kotasync make)
    if [[ -e ".ota/${latest_nightly}" ]]; then
        cmd+=(--reorder ".ota/${latest_nightly}")
    fi
    cmd+=("${txz}" "${kotasync}")
    container_exec "${cmd[@]}"
    latest_make copy "${kotasync}" "${latest}" "${latest_nightly}"
}

zsync_make() {
    [[ $# -eq 4 ]] || return
    local tgz="$1" zsync="$2" latest="$3" latest_nightly="$4"
    local cmd=(zsyncmake "${tgz}" -C -u "${tgz##*/}" -o "${zsync}")
    container_exec "${cmd[@]}"
    latest_make copy "${zsync}" "${latest}" "${latest_nightly}"
}

# Fetch latest nightly kotasync files.
if out="$(run gh release view --json assets --jq '.assets[].name | select(test("^koreader-.*-latest-nightly\\.kotasync$"))' "${OTA_RELEASE}")" && [[ -n "${out}" ]]; then
    run gh release download --dir="${assets_dir}/.ota" --pattern='koreader-*-latest-nightly.kotasync' "${OTA_RELEASE}"
    # shellcheck disable=SC2016
    onexit 'run rm -rf "${assets_dir}/.ota"'
fi

# Parse initial list of assets.
initial_assets="$("${CI_DIR}/assets_parse_to_sh.sh" "${assets_dir}"/*)"

printf '%s\n' "${ANSI_DIM}pushd $(quote "${assets_dir}")${ANSI_RESET}" 1>&2
pushd "${assets_dir}" >/dev/null || exit

run cp "${CI_DIR%/*}/tools/mkrelease.sh" .mkrelease.sh

# Start helper container.
container_start

while read -r line; do
    declare -A asset="(${line})"
    asset[file]="${asset[file]##*/}"

    printf '%s\n' "${ANSI_GREEN}${asset[platform_name]}: ${asset[file]}${ANSI_RESET}"

    latest_files=("koreader-${asset[platform]}"-latest-{"${channel}",nightly})

    case "${asset[platform]}.${asset[extension]}" in

        android-arm.apk) latest_files=("${latest_files[@]/-android-arm-/-android-}") ;&
        android-*.apk)
            latest_make link "${asset[file]}" "${latest_files[@]}"
            if [[ "${asset[stable]}" == 'true' ]] && [[ "${asset[commit_hash]}" ]]; then
                commit_count="$(git rev-list --count "v${asset[base_version]}")"
                run sh -c "printf '%s\n%u\n' 'v${asset[version]}' '${commit_count}' >koreader-android-fdroid-latest"
            fi
            ;;

        cervantes.zip | kindle*.zip | kobo*.zip | pocketbook*.zip | remarkable*.zip)
            stem="${asset[file]%.zip}"
            # New OTA.
            release_make "${stem}.tar.xz" "${asset[file]}"
            kotasync_make "${stem}.tar.xz" "${stem}.kotasync" "${latest_files[@]/%/.kotasync}"
            # Old OTA.
            case "${asset[platform]}" in
                kobo*) opts=('--manifest=koreader/ota/package.index') pats=('-x!koreader.png') ;;
                pocketbook*) opts=('--manifest=applications/koreader/ota/package.index' '--manifest-transform=s/^/..\//') pats=('-x!system') ;;
                *) opts=() pats=() ;;
            esac
            release_make "${opts[@]}" "${stem}.targz" "${asset[file]}" "${pats[@]}"
            zsync_make "${asset[file]}" "${stem}.zsync" "${latest_files[@]/%/.zsync}"
            ;;

        linux-*.AppImage) latest_make link "${asset[file]}" "${latest_files[@]/-linux-/-appimage-}" ;;
        linux-*.deb) latest_make link "${asset[file]}" "${latest_files[@]/-linux-/-debian-}" ;;
        linux-*.tar.xz) latest_make link "${asset[file]}" "${latest_files[@]}" ;;

    esac

done <<<"${initial_assets}"

printf '%s\n' "${ANSI_DIM}popd${ANSI_RESET}" 1>&2
popd >/dev/null || exit

# vim: sw=4
