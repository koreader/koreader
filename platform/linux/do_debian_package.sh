#!/bin/bash

set -eo pipefail
# Script to generate debian packages for KOReader

declare -r USAGE="
USAGE:
    $0 OUTPUT_DEB INPUT_DIR [EXTRA_DPKG-DEB_OPTION]…
"

command_exists() {
    type "$1" >/dev/null 2>/dev/null
}

write_changelog() {
    CHANGELOG_PATH="${1}/usr/share/doc/koreader/changelog.Debian.gz"
    CHANGELOG=$(
        cat <<END_HEREDOC
koreader ($2) stable; urgency=low

  * Changelog is available at https://github.com/koreader/koreader/releases

 -- koreader <null@koreader.rocks>  $(date -R)

koreader (2025.04) unstable; urgency=low

  * don't use debian fonts: https://github.com/koreader/koreader/issues/13509

 -- koreader <null@koreader.rocks>  Thu, 10 Apr 2025 00:00:00 +0200

koreader (0.0.1) experimental; urgency=low

  * initial release as debian package: https://github.com/koreader/koreader/issues/3108

 -- koreader <null@koreader.rocks>  Tue, 03 Jan 2019 00:00:00 +0100
END_HEREDOC
    )

    echo "${CHANGELOG}" | gzip -cn9 >"${CHANGELOG_PATH}"
    chmod 644 "${CHANGELOG_PATH}"
}

if [[ $# -lt 2 ]]; then
    echo "${USAGE}" 1>&2
    exit 1
fi

output_deb="$1"
input_dir="$2"
shift 2

# Check for required tools.
missing_tools=()
# shellcheck disable=SC2043
for tool in dpkg-deb; do
    if ! command_exists "${tool}"; then
        missing_tools+=("${tool}")
    fi
done
if [[ ${#missing_tools[@]} -ne 0 ]]; then
    echo "${0}: unable to build Debian package, the following tools are missing: ${missing_tools[*]}" 1>&2
    exit 1
fi

IFS=_ read -r _package version arch <<<"${output_deb##*/}"
arch="${arch%.*}"

# populate debian control file
mkdir -p "${input_dir}/DEBIAN"
cat >"${input_dir}/DEBIAN/control" <<EOF
Section: graphics
Priority: optional
Depends: libc6 (>= 2.34), libdecor-0-0 (>= 0.1.0), libdrm2 (>= 2.4.46), libgbm1 (>= 8.1~0), libwayland-client0 (>= 1.20.0), libwayland-cursor0 (>= 1.0.2), libwayland-egl1 (>= 1.15.0), libx11-6 (>= 2:1.2.99.901), libxcursor1 (>> 1.1.2), libxext6, libxfixes3 (>= 1:5.0), libxi6 (>= 2:1.5.99.2), libxkbcommon0 (>= 0.5.0), libxrandr2 (>= 2:1.2.99.3), libxss1
Architecture: ${arch}
Version: ${version}
Installed-Size: $(du -ks "${input_dir}/usr/" | cut -f 1)
Package: koreader
Maintainer: koreader <null@koreader.rocks>
Homepage: https://koreader.rocks
Description: Ebook reader optimized for e-ink screens.
 It can open many formats and provides advanced text adjustments.
 .
 See below for a selection of its many features:
 .
 Supports both fixed page formats (PDF, DjVu, CBT, CBZ)
 and reflowable e-book formats (EPUB, FB2, Mobi, DOC, CHM, TXT, HTML).
 Scanned PDF/DjVu documents can be reflowed.
 Special flow directions for reading double column PDFs and manga.
 .
 Multi-lingual user interface optimized for e-ink screens.
 Highly customizable reader view with complete typesetting options.
 Multi-lingual hyphenation dictionaries are bundled in.
 .
 Non-Latin script support for books, including the Hebrew, Arabic,
 Persian, Russian, Chinese, Japanese and Korean languages.
 .
 Unique Book Map and Page Browser features to navigate your book.
 .
 Special multi-page highlight mode with many local and online export options.
 .
 Can synchronize your reading progress across all your KOReader running devices.
 .
 Integrated with Calibre, Wallabag, Wikipedia,
 Google Translate and other content providers.
EOF

# use absolute path to luajit in reader.lua
sed -i 's,./luajit,/usr/lib/koreader/luajit,' "${input_dir}/usr/lib/koreader/reader.lua"

# lintian complains if shared libraries have execute rights.
find "${input_dir}" -type f -perm /+x -name '*.so*' -print0 | xargs -0 chmod a-x

# remove misc files that are already summarized in usr/share/doc/koreader
find "${input_dir}" '(' -name "*.md" -o -name "LICENSE" ')' -type f -print0 | xargs -0 rm -rf

# add debian changelog
write_changelog "${input_dir}" "${version}"

dpkg-deb --build --root-owner-group "${@}" "${input_dir}" "${output_deb}"
