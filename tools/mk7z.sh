#!/usr/bin/env bash

set -eo pipefail
# set -x

[[ $# -ge 3 ]]
archive="$(realpath "$1")"
epoch="$2"
shift 2
options=()
for a in "$@"; do
    shift
    case "${a}" in
        --) break ;;
        -*) options+=("${a}") ;;
        *) break ;;
    esac
done
[[ $# -gt 0 ]]
patterns=("$@")

# We need to use the full path to the executable to avoid
# a weird issue when using the p7zip project pre-built
# binary (`Can't load './7z.dll' (7z.so)...`).
sevenzip="$(which 7z)"

# echo "archive : ${archive}"
# echo "epoch   : ${epoch}"
# echo "options : ${options[@]}"
# echo "patterns: ${patterns[@]}"

tmpdir="$(mktemp -d -t tmp7z.XXXXXXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

manifest="${tmpdir}/manifest"

# Detect if that version of 7z deferences symlinks by default.
sevenzip_manifest_cmd=("${sevenzip}" -ba h)
ln -s /dev/null "${tmpdir}/symlink"
checksum="$("${sevenzip_manifest_cmd[@]}" "${tmpdir}/symlink" | awk '{ print $1 }')"
if [[ "${checksum}" != '00000000' ]]; then
    sevenzip_manifest_cmd+=(-l)
fi
rm -f "${tmpdir}/symlink"

# Note: remove trailing `/` appended to directories in some 7z versions.
"${sevenzip_manifest_cmd[@]}" "${patterns[@]}" |
    awk '{ if ($3!="") print $3, $2, $1; else { gsub("/$", "", $1); print $1 } }' |
    sort >"${manifest}"

# cat "${manifest}" | less

if [[ -r "${archive}" ]]; then
    if diff --brief --label 'in archive' \
        <(
            "${sevenzip}" -slt l "${archive}" |
                awk '
                    /^([^=]+) = / { entry[$1] = $3; }
                    /^CRC =/ { if ($3!="") print entry["Path"], entry["Size"], $3; else print entry["Path"] }
                    ' | sort
        ) --label 'to add' "${manifest}"; then
        exit
    fi
    # There's no 7z option to overwrite the archive
    # if it already exists (instead of updating it)…
    rm -f "${archive}"
fi

# Extract list of paths from manifest.
rev <"${manifest}" | cut -f3- -d' ' | rev >"${tmpdir}/paths"
# Quick sanity check: no path outside the current directory.
if grep '^(/|\.\./)' <"${tmpdir}/paths"; then
    echo "^ some paths are outside the current directory!"
    exit 1
fi

# Make a copy of everything so we can later
# patch timestamp to ensure reproducibility.
mkdir "${tmpdir}/contents"
# We want to copy "empty" (with ignored files) directories.
tar --dereference --no-recursion --create \
    --verbatim-files-from --files-from="${tmpdir}/paths" |
    tar --extract --directory="${tmpdir}/contents"

cd "${tmpdir}/contents"

# Fix timestamps.
find . -depth -print0 | xargs -0 touch --date="${epoch}"

# And create the final archive.
"${sevenzip}" -mqs "${options[@]}" a "${archive}" .

# vim: sw=4
