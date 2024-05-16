#!/bin/bash

set -eo pipefail
# Script to generate debian packages for KOReader

command_exists() {
    type "$1" >/dev/null 2>/dev/null
}

link_fonts() {
    syspath="../../../../share/fonts/truetype/$(basename "$1")"
    for FILE in "$1"/*.ttf; do
        ln -snf "${syspath}/${FILE##*/}" "${FILE}"
    done
}

uname_to_debian() {
    case "$1" in
        x86_64) echo "amd64" ;;
        armv7l) echo "armhf" ;;
        aarch64) echo "arm64" ;;
        *) echo "$1" ;;
    esac
}

write_changelog() {
    CHANGELOG_PATH="${1}/share/doc/koreader/changelog.Debian.gz"
    CHANGELOG=$(
        cat <<'END_HEREDOC'
koreader (0.1) unstable; urgency=low

  * Fixes most lintian errors and warnings

 -- Martín Fdez <paziusss@gmail.com>  Thu, 14 May 2020 00:00:00 +0100

koreader (0.0.1) experimental; urgency=low

  * Initial release as Debian package (Closes: https://github.com/koreader/koreader/issues/3108)

 -- Martín Fdez <paziusss@gmail.com>  Tue, 03 Jan 2019 00:00:00 +0100
END_HEREDOC
    )

    echo "${CHANGELOG}" | gzip -cn9 >"${CHANGELOG_PATH}"
    chmod 644 "${CHANGELOG_PATH}"
}

if ! [ -r "${1}" ]; then
    echo "${0}: can't find KOReader archive, please specify a path to a KOReader tar.gz" 1>&2
    exit 1
fi

# Check for required tools.
missing_tools=()
for tool in dpkg-deb fakeroot; do
    if ! command_exists "${tool}"; then
        missing_tools+=("${tool}")
    fi
done
if [[ ${#missing_tools[@]} -ne 0 ]]; then
    echo "${0}: unable to build Debian package, the following tools are missing: ${missing_tools[*]}" 1>&2
    exit 1
fi

mkdir -p tmp-debian/usr
chmod 0755 tmp-debian/usr
tar -xf "${1}" -C tmp-debian/usr
rm -f tmp-debian/usr/koreader.appdata.xml
ARCH="$(echo "${1}" | cut -d '-' -f3)"
VERSION="$(cut -f2 -dv "tmp-debian/usr/lib/koreader/git-rev" | cut -f1,2 -d-)"
DEB_ARCH="$(uname_to_debian "${ARCH}")"
BASE_DIR="tmp-debian"

# populate debian control file
mkdir -p "${BASE_DIR}/DEBIAN"
cat >"${BASE_DIR}/DEBIAN/control" <<EOF
Section: graphics
Priority: optional
Depends: libsdl2-2.0-0, fonts-noto-hinted, fonts-droid-fallback, libc6 (>= 2.31)
Architecture: ${DEB_ARCH}
Version: ${VERSION}
Installed-Size: $(du -ks "${BASE_DIR}/usr/" | cut -f 1)
Package: koreader
Maintainer: Martín Fdez <paziusss@gmail.com>
Homepage: https://koreader.rocks
Description: Ebook reader application supporting PDF, DjVu, EPUB, FB2 and many more formats
 KOReader is a document viewer for E Ink devices.
 Supported fileformats include EPUB, PDF, DjVu, XPS, CBT,
 CBZ, FB2, PDB, TXT, HTML, RTF, CHM, DOC, MOBI and ZIP files.
 It’s available for Kindle, Kobo, PocketBook, Android and desktop Linux.
EOF

# use absolute path to luajit in reader.lua
sed -i 's,./luajit,/usr/lib/koreader/luajit,' "${BASE_DIR}/usr/lib/koreader/reader.lua"

# use debian packaged fonts instead of our embedded ones to save a couple of MB.
# Note: avoid linking against fonts-noto-cjk-extra, cause it weights ~200MB.
link_fonts "${BASE_DIR}/usr/lib/koreader/fonts/noto"

# DroidSansMono has a restrictive license. Replace it with DroidSansFallback
ln -snf ../../../../share/fonts-droid-fallback/truetype/DroidSansFallback.ttf "${BASE_DIR}/usr/lib/koreader/fonts/droid/DroidSansMono.ttf"

# lintian complains if shared libraries have execute rights.
find "${BASE_DIR}" -type f -perm /+x -name '*.so*' -print0 | xargs -0 chmod a-x

# add debian changelog
write_changelog "${BASE_DIR}/usr"

fakeroot dpkg-deb -b "${BASE_DIR}" "koreader-${VERSION}-${DEB_ARCH}.deb"
rm -rf tmp-debian
