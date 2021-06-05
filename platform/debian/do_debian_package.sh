#!/bin/bash
# Script to generate debian packages for KOReader
if [ -z "${1}" ]; then
    echo "${0}: can't find KOReader build, please specify a path"
    exit 1
else
    INSTALL_DIR="${1}"
    VERSION="$(cut -f2 -dv "${1}/koreader/git-rev" | cut -f1,2 -d-)"
fi

uname_to_debian() {
    if [ "$(uname -m)" == "x86_64" ]; then
        echo "amd64"
    elif [ "$(uname -m)" == "i686" ]; then
        echo "i686"
    elif [ "$(uname -m)" == "arm64" ]; then
        echo "aarch64"
    else
        echo "any"
    fi
}

link_fonts() {
    syspath="../../../../share/fonts/truetype/$(basename "${1}")"
    for FILE in *.ttf; do
        rm -rf "${FILE}"
        ln -s "${syspath}/${FILE}" "${FILE}"
    done
}

if [ -z "${2}" ]; then
    ARCH="$(uname_to_debian)"
else
    ARCH="${2}"
fi

command_exists() {
    type "$1" >/dev/null 2>/dev/null
}

# Run only if dpkg-deb exists
COMMAND="dpkg-deb"
if command_exists "${COMMAND}"; then
    BASE_DIR="${INSTALL_DIR}/debian/usr"

    # populate debian control file
    mkdir -p "${INSTALL_DIR}/debian/DEBIAN"
    {
        echo "Section: graphics"
        echo "Priority: optional"
        echo "Depends: libsdl2-2.0-0, fonts-noto-hinted, fonts-droid-fallback, libc6 (>= 2.2.3)"
        echo "Architecture: ${ARCH}"
        echo "Version: ${VERSION}"
        echo "Installed-Size: $(du -ks "${INSTALL_DIR}/debian/usr/" | cut -f 1)"
        echo "Package: koreader"
        echo "Maintainer: Martín Fdez <paziusss@gmail.com>"
        echo "Homepage: https://koreader.rocks"
        echo "Description: Ebook reader application supporting PDF, DjVu, EPUB, FB2 and many more formats"
        echo " KOReader is a document viewer for E Ink devices."
        echo " Supported fileformats include EPUB, PDF, DjVu, XPS, CBT,"
        echo " CBZ, FB2, PDB, TXT, HTML, RTF, CHM, DOC, MOBI and ZIP files."
        echo " It’s available for Kindle, Kobo, PocketBook, Android and desktop Linux."

    } >"${INSTALL_DIR}/debian/DEBIAN/control"

    # remove leftovers
    find "${BASE_DIR}" -type f -name ".git" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}" -type f -name ".gitignore" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}" -type f -name "discovery2spore" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}" -type f -name "wadl2spore" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}" -type d -name "test" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}" -type f -name "*.txt" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}" -type f -name "LICENSE" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}" -type f -name "NOTICE" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}" -type f -name "README.md" -print0 | xargs -0 rm -rf
    find "${BASE_DIR}/lib" -type f -name "COPYING" -print0 | xargs -0 rm -rf

    # fix permissions
    find "${BASE_DIR}" -type d -print0 | xargs -0 chmod 755
    find "${BASE_DIR}" -executable -type f -print0 | xargs -0 chmod 755
    find "${BASE_DIR}" -type f -name "*.cff" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.crt" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.html" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.lua" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*manifest" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.pattern" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.png" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.otf" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.po*" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.so*" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "*.ttf" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "git-rev" -print0 | xargs -0 chmod 644
    find "${BASE_DIR}" -type f -name "reader.lua" -print0 | xargs -0 chmod 755

    # use absolute path to luajit in reader.lua
    sed -i 's/.\/luajit/\/usr\/lib\/koreader\/luajit/' "${BASE_DIR}/lib/koreader/reader.lua"

    # use debian packaged fonts instead of our embedded ones to save a couple of MB.
    # Note: avoid linking against fonts-noto-cjk-extra, cause it weights ~200MB.
    (cd "${BASE_DIR}/lib/koreader/fonts/noto" && link_fonts "$(pwd)")

    # DroidSansMono has a restrictive license. Replace it with DroidSansFallback
    (
        cd "${BASE_DIR}/lib/koreader/fonts/droid" && rm -rf DroidSansMono.ttf &&
            ln -s ../../../../share/fonts-droid-fallback/truetype/DroidSansFallback.ttf DroidSansMono.ttf
    )

    # try to remove rpath
    if command_exists chrpath; then
        find "${BASE_DIR}/lib/koreader/libs" -type f -name "*.so*" -print0 | xargs -0 chrpath -d
    else
        echo "chrpath tool not found. Skipping RPATH deletion"
    fi

    (cd "${INSTALL_DIR}/.." &&
        fakeroot dpkg-deb -b "${INSTALL_DIR}/debian" "koreader-${VERSION}-${ARCH}.deb")
else
    echo "${COMMAND} not found, unable to build Debian package"
    exit 1
fi
