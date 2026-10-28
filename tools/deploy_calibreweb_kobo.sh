#!/usr/bin/env bash
# Copies the Calibre-Web (OPDS plugin) changes onto a Kobo connected over USB, from WSL.
#
# Usage: tools/deploy_calibreweb_kobo.sh [DRIVE_LETTER] [--dry-run]
#   DRIVE_LETTER  Windows drive letter of the Kobo (default: auto-detect the "KOBOeReader" volume)
#   --dry-run     show what would be copied without mounting or copying
#
# On the Kobo, tap "Connect" when plugged in so it shows up as a drive in Windows first.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES=(
    plugins/opds.koplugin/calibrewebclient.lua
    plugins/opds.koplugin/calibrewebbrowser.lua
    plugins/opds.koplugin/calibrewebitem.lua
    plugins/opds.koplugin/calibrewebindex.lua
    plugins/opds.koplugin/opdsclient.lua
    plugins/opds.koplugin/main.lua
    frontend/ui/elements/filemanager_menu_order.lua
)

DRIVE=""
DRY_RUN=0
for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        [A-Za-z] | [A-Za-z]:) DRIVE="${arg:0:1}" ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            exit 2
            ;;
    esac
done

if [[ -z "${DRIVE}" ]]; then
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo "Cannot auto-detect the Kobo outside WSL: pass the drive letter, e.g. $0 D" >&2
        exit 1
    fi
    DRIVE="$(powershell.exe -NoProfile -Command \
        "(Get-Volume | Where-Object FileSystemLabel -eq 'KOBOeReader' | Select-Object -First 1).DriveLetter" \
        2>/dev/null | tr -d '\r\n ')"
    if [[ -z "${DRIVE}" ]]; then
        echo "No Kobo found. Plug it in, tap \"Connect\" on the Kobo, then run this again." >&2
        exit 1
    fi
fi
DRIVE="${DRIVE^^}"
MNT="/mnt/${DRIVE,,}"
KO="${MNT}/.adds/koreader"

for f in "${FILES[@]}"; do
    [[ -f "${REPO_DIR}/${f}" ]] || {
        echo "Missing source file: ${f}" >&2
        exit 1
    }
done

echo "Kobo drive: ${DRIVE}: (mount point ${MNT})"
if ((DRY_RUN)); then
    for f in "${FILES[@]}"; do echo "would copy ${f} -> ${KO}/${f}"; done
    exit 0
fi

MOUNTED_HERE=0
if ! mountpoint -q "${MNT}"; then
    sudo mkdir -p "${MNT}"
    sudo mount -t drvfs "${DRIVE}:" "${MNT}"
    MOUNTED_HERE=1
fi
cleanup() {
    sync
    if ((MOUNTED_HERE)); then sudo umount "${MNT}" || echo "Warning: could not unmount ${MNT}" >&2; fi
}
trap cleanup EXIT

if [[ ! -d "${KO}/plugins/opds.koplugin" ]]; then
    echo "KOReader not found at ${KO} (is this the Kobo, and is KOReader installed?)" >&2
    exit 1
fi

for f in "${FILES[@]}"; do
    cp "${REPO_DIR}/${f}" "${KO}/${f}"
    if cmp -s "${REPO_DIR}/${f}" "${KO}/${f}"; then
        echo "  copied  ${f}"
    else
        echo "  FAILED  ${f} (copy differs)" >&2
        exit 1
    fi
done

echo "Done. Eject the Kobo in Windows (Safely Remove), then restart KOReader."
