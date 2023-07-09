#!/bin/bash

# Script to generate debian packages for KOReader

command_exists() {
    type "$1" >/dev/null 2>/dev/null
}

link_fonts() {
    syspath="../../../../share/fonts/truetype/$(basename "${1}")"
    for FILE in *.ttf; do
        rm -rf "${FILE}"
        ln -s "${syspath}/${FILE}" "${FILE}"
    done
}

uname_to_debian() {
    if [ "${1}" == "x86_64" ]; then
        echo "amd64"
    elif [ "${1}" == "armv7l" ]; then
        echo "armhf"
    elif [ "${1}" == "aarch64" ]; then
        echo "arm64"
    else
        echo "${1}"
    fi
}

write_changelog() {
    CHANGELOG_PATH="${1}/share/doc/koreader/changelog.Debian.gz"
    CHANGELOG=$(cat << 'END_HEREDOC'
koreader (0.1) unstable; urgency=low

  * Fixes most lintian errors and warnings

 -- Martín Fdez <paziusss@gmail.com>  Thu, 14 May 2020 00:00:00 +0100

koreader (0.0.1) experimental; urgency=low

  * Initial release as Debian package (Closes: https://github.com/koreader/koreader/issues/3108)

 -- Martín Fdez <paziusss@gmail.com>  Tue, 03 Jan 2019 00:00:00 +0100
END_HEREDOC
)

echo "${CHANGELOG}" | gzip -cn9 > "${CHANGELOG_PATH}"
chmod 644 "${CHANGELOG_PATH}"
}


if [ -z "${1}" ]; then
    echo "${0}: can't find KOReader archive, please specify a path to a KOReader tar.gz"
    exit 1
else
    mkdir -p tmp-debian/usr
    chmod 0755 tmp-debian/usr
    tar -xf "${1}" -C tmp-debian/usr
    ARCH="$(echo "${1}" | cut -d '-' -f3)"
    VERSION="$(cut -f2 -dv "tmp-debian/usr/lib/koreader/git-rev" | cut -f1,2 -d-)"
    DEB_ARCH="$(uname_to_debian "${ARCH}")"
fi

# Run only if dpkg-deb exists
COMMAND="dpkg-deb"
if command_exists "${COMMAND}"; then
    BASE_DIR="tmp-debian"

    # populate debian control file
    mkdir -p "${BASE_DIR}/DEBIAN"
    {
        echo "Section: graphics"
        echo "Priority: optional"
        echo "Depends: libsdl2-2.0-0, fonts-noto-hinted, fonts-droid-fallback, libc6 (>= 2.2.3)"
        echo "Architecture: ${DEB_ARCH}"
        echo "Version: ${VERSION}"
        echo "Installed-Size: $(du -ks "${BASE_DIR}/usr/" | cut -f 1)"
        echo "Package: koreader"
        echo "Maintainer: Martín Fdez <paziusss@gmail.com>"
        echo "Homepage: https://koreader.rocks"
        echo "Description: Ebook reader application supporting PDF, DjVu, EPUB, FB2 and many more formats"
        echo " KOReader is a document viewer for E Ink devices."
        echo " Supported fileformats include EPUB, PDF, DjVu, XPS, CBT,"
        echo " CBZ, FB2, PDB, TXT, HTML, RTF, CHM, DOC, MOBI and ZIP files."
        echo " It’s available for Kindle, Kobo, PocketBook, Android and desktop Linux."

    } > "${BASE_DIR}/DEBIAN/control"

    # use absolute path to luajit in reader.lua
    sed -i 's/.\/luajit/\/usr\/lib\/koreader\/luajit/' "${BASE_DIR}/usr/lib/koreader/reader.lua"

    # use debian packaged fonts instead of our embedded ones to save a couple of MB.
    # Note: avoid linking against fonts-noto-cjk-extra, cause it weights ~200MB.
    (cd "${BASE_DIR}/usr/lib/koreader/fonts/noto" && link_fonts "$(pwd)")

    # DroidSansMono has a restrictive license. Replace it with DroidSansFallback
    (
        cd "${BASE_DIR}/usr/lib/koreader/fonts/droid" && rm -rf DroidSansMono.ttf &&
            ln -s ../../../../share/fonts-droid-fallback/truetype/DroidSansFallback.ttf DroidSansMono.ttf
    )

    # add debian changelog
    write_changelog "${BASE_DIR}/usr"

    # try to remove rpath
    if command_exists chrpath; then
        find "${BASE_DIR}/usr/lib/koreader/libs" -type f -name "*.so*" -print0 | xargs -0 chrpath -d
    else
        echo "chrpath tool not found. Skipping RPATH deletion"
    fi

    fakeroot dpkg-deb -b "${BASE_DIR}" "koreader-${VERSION}-${DEB_ARCH}.deb"
else
    echo "${COMMAND} not found, unable to build Debian package"
    exit 1
fi


rm -rf tmp-debian

#echo "${1} -> koreader-$DEB_ARCH-$VERSION.deb"
