#!/usr/bin/env bash

set -eo pipefail
# set -x

declare -r USAGE="
USAGE:
    $0 [OPTIONS] [--] ARCHIVE_NAME|DIRECTORY/ [PATTERNS]

OPTIONS:
    -j N, --jobs N               use up to N processes / threads
    -e EPOCH, --epoch EPOCH      set contents timestamp to EPOCH
    -m ENTRY, --manifest ENTRY   add a manifest ENTRY to the release
    --manifest-transform SCRIPT  transform manifest using sed SCRIPT
    -o OPTS, --options OPTS      forward options to compressor
"

# Note: we ignore directories (entries with no CRC).
# shellcheck disable=SC2016
declare -r AWK_HELPERS='
function print_entry(path, size, crc) {
    if (crc != "")
        print path, size, crc
}
function reverse_entry() {
    $0 = $3" "$2" "$1;
}
'

if [[ "${OSTYPE}" = darwin* ]]; then
    declare -r READLINK=greadlink
    declare -r TAR=gtar
else
    declare -r READLINK=readlink
    declare -r TAR=tar
fi

if ! opt=$(getopt -o '+de:hj:m:o:' --long 'debug,epoch:,help,jobs:,manifest:,manifest-transform:,options:' --name "$0" -- "$@"); then
    echo "${USAGE}"
    exit 1
fi

# Arguments parsing. {{{

debug=''
epoch=''
jobs=''
manifest=''
manifest_transform=''
options=()

eval set -- "${opt}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d | --debug)
            debug=1
            ;;
        -e | --epoch)
            epoch="$2"
            shift
            ;;
        -h | --help)
            echo "${USAGE}"
            exit 0
            ;;
        -j | --jobs)
            jobs="$2"
            shift
            ;;
        -m | --manifest)
            manifest="$2"
            shift
            ;;
        --manifest-transform)
            manifest_transform="$2"
            shift
            ;;
        -o | --options)
            declare -a a="($2)"
            options+=("${a[@]}")
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
    shift
done

if [[ $# -lt 1 ]]; then
    echo "${USAGE}"
    exit 1
fi

case "$1" in
    */) format='/' ;;
    *.7z | *.zip) format="${1##*.}" ;;
    *.tar.gz | *.targz) format=tar.gz ;;
    *.tar.xz) format=tar.xz ;;
    *.tar.zst) format=tar.zst ;;
    *)
        echo "ERROR: unsupported release format: ${1##*.}" 1>&2
        exit 2
        ;;
esac
output="$("${READLINK}" -f "$1")"
shift
patterns=("$@")
if [[ -n "${manifest}" ]]; then
    patterns+=("-x!${manifest}")
fi

# }}}

if command -v pv >/dev/null; then
    write_to_file() {
        pv --interval=0.25 --bytes --timer --rate --output="$1"
    }
else
    write_to_file() {
        dd bs=4096 of="$1"
    }
fi

# Ensure a "traditional" sort order.
export LC_ALL=C

# We need to use the full path to the executable to avoid
# a weird issue when using the p7zip project pre-built
# binary (`Can't load './7z.dll' (7z.so)...`).
if ! sevenzip="$(which 7z)"; then
    echo "ERROR: 7z executable not found!" 1>&2
    exit 2
fi
sevenzip_compress_cmd=("${sevenzip}")

# Setup temporary directory.
tmpdir="$(mktemp -d -t tmp7z.XXXXXXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT
mkdir -p "${tmpdir}/contents"

# Detect if that version of 7z deferences symlinks by default.
sevenzip_manifest_cmd=("${sevenzip}" -ba h)
ln -s /dev/null "${tmpdir}/symlink"
checksum="$("${sevenzip_manifest_cmd[@]}" "${tmpdir}/symlink" | awk '{ print $1 }')"
if [[ "${checksum}" != '00000000' ]]; then
    sevenzip_manifest_cmd+=(-l)
fi
rm -f "${tmpdir}/symlink"

# Prefer `pigz` over `gzip` (faster).
gzip="$(command -v pigz || command -v gzip)"
gzip_cmd=("${gzip}")

# Jobs.
if [[ -n "${jobs}" ]]; then
    [[ "${gzip}" != */pigz ]] || gzip_cmd+=(--processes "${jobs}")
    sevenzip_compress_cmd+=(-mmt="${jobs}")
fi

# In-place sed command.
if [[ "${OSTYPE}" = darwin* ]]; then
    ised=(sed -i '' -e)
else
    ised=(sed -i -e)
fi

if [[ -n "${debug}" ]]; then
    echo "format              : ${format}"
    echo "output              : ${output}"
    echo "manifest            : ${manifest}"
    echo "manifest transform  : ${manifest_transform}"
    echo "epoch               : ${epoch}"
    echo "options             : ${options[*]@Q}"
    echo "patterns            : ${patterns[*]@Q}"
    echo "7z executable       : ${sevenzip}"
    echo "7z compress command : ${sevenzip_compress_cmd[*]@Q}"
    echo "7z manifest command : ${sevenzip_manifest_cmd[*]@Q}"
    echo "gzip executable     : ${gzip}"
    echo "gzip command        : ${gzip_cmd[*]@Q}"
    echo "sed in-place command: ${ised[*]@Q}"
    [[ -t 0 ]] && read -srn 1
fi

# Build manifest.
"${sevenzip_manifest_cmd[@]}" "${patterns[@]}" |
    awk "${AWK_HELPERS}"'{ reverse_entry(); print_entry($1, $2, $3) }' |
    sort -o "${tmpdir}/manifest"

# Extract list of paths from manifest.
rev <"${tmpdir}/manifest" | cut -f3- -d' ' | rev >"${tmpdir}/paths"
# Quick sanity check: no path outside the current directory.
if grep '^(/|\.\./)' <"${tmpdir}/paths"; then
    echo "ERROR: ^ some paths are outside the current directory!"
    exit 2
fi

# Don't forget the archive's internal manifest, if requested.
if [[ -n "${manifest}" ]]; then
    {
        cat "${tmpdir}/paths"
        printf '%s\n' "${manifest}"
    } | sort -u -o "${tmpdir}/paths_with_manifest"
    install --mode=0644 -D "${tmpdir}/paths_with_manifest" "${tmpdir}/contents/${manifest}"
    if [[ -n "${manifest_transform}" ]]; then
        "${ised[@]}" "${manifest_transform}" "${tmpdir}/contents/${manifest}"
    fi
    # Can't use 7z's `-w` option in this case…
    pushd "${tmpdir}/contents" >/dev/null
    "${sevenzip[@]}" -ba h |
        awk "${AWK_HELPERS}"'{ reverse_entry(); print_entry($1, $2, $3) }' >>"${tmpdir}/manifest"
    popd >/dev/null
    sort -u -o "${tmpdir}/manifest" "${tmpdir}/manifest"
fi

if [[ -n "${debug}" ]] && [[ -t 0 ]]; then
    paths=("${tmpdir}/manifest" "${tmpdir}"/paths*)
    [[ -z "${manifest}" ]] || paths+=("${tmpdir}/contents/${manifest}")
    less "${paths[@]}"
fi

# If the output already exists, check for changes.
if [[ -r "${output}" ]]; then
    previous_manifest=''
    case "${format}" in
        /) ;;
        tar*) ;;
        *)
            previous_manifest="$(
                "${sevenzip[@]}" -ba -slt l "${output}" |
                    awk "${AWK_HELPERS}"'
                        /^[^=]+ = / { e[$1] = $3; }
                        /^$/ && e["Size"] != "" {
                            # Handle empty files (no CRC).
                            if (e["CRC"] == "" && e["Attributes"] !~ /^D/ && e["Size"] == 0)
                                e["CRC"] = "00000000";
                            print_entry(e["Path"], e["Size"], e["CRC"])
                        }
                        ' | sort
            )"
            ;;
    esac
    if [[ -n "${previous_manifest}" ]] &&
        diff --color${CLICOLOR_FORCE:+=always} --unified \
            --label 'old' <(printf '%s\n' "${previous_manifest}") \
            --label 'new' "${tmpdir}/manifest"; then
        exit
    fi
    # There's no 7z or zip option to overwrite the output
    # if it already exists (instead of updating it), and
    # it may be a directory anyway…
    rm -rf "${output}"
fi

# Make a copy of everything so we can later patch timestamps and
# fix permissions to ensure reproducibility.
"${TAR}" --create --dereference --hard-dereference --no-recursion \
    --verbatim-files-from --files-from="${tmpdir}/paths" |
    "${TAR}" --extract --directory="${tmpdir}/contents"

cd "${tmpdir}/contents"

# Fix permissions.
chmod -R u=rwX,og=rX .

# Fix timestamps.
if [[ -n "${epoch}" ]]; then
    find . -depth -print0 | xargs -0 touch --date="${epoch}"
fi

# And create the final output.
if [[ -n "${manifest}" ]]; then
    filelist="${tmpdir}/paths_with_manifest"
else
    filelist="${tmpdir}/paths"
fi
sevenzip_compress_cmd+=("${options[@]}" a "${output}" "-i@${filelist}")
tar_compress_cmd=(
    "${TAR}" --create --no-recursion
    --numeric-owner --owner=0 --group=0
    # Minimize size of terminating empty blocks (7KB → 1KB).
    --record-size=512
    --verbatim-files-from --files-from="${filelist}"
)
case "${format}" in
    /)
        mv "${tmpdir}/contents" "${output}"
        ;;
    7z)
        # Note: sort by type (for better compression).
        "${sevenzip_compress_cmd[@]}" -mqs
        ;;
    tar.gz)
        echo "Creating archive: ${output}"
        # Note: create a rsyncable gzipped tar.
        "${tar_compress_cmd[@]}" |
            "${gzip}" -9 --no-name --rsyncable "${options[@]}" --stdout |
            write_to_file "${output}"
        ;;
    tar.xz)
        echo "Creating archive: ${output}"
        "${tar_compress_cmd[@]}" |
            xz -9 ${jobs:+--threads=${jobs}} "${options[@]}" |
            write_to_file "${output}"
        ;;
    tar.zst)
        echo "Creating archive: ${output}"
        "${tar_compress_cmd[@]}" |
            zstd -19 ${jobs:+--threads=${jobs}} "${options[@]}" --stdout |
            write_to_file "${output}"
        ;;
    zip)
        "${sevenzip_compress_cmd[@]}" -tzip
        ;;
esac

# vim: foldmethod=marker foldlevel=0 sw=4
