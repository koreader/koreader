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
if command_exists "$COMMAND"; then
    mkdir -p "${INSTALL_DIR}/debian/DEBIAN"
    {
        echo "Section: graphics"
        echo "Priority: optional"
        echo "Depends: libsdl2-2.0-0"
        echo "Architecture: ${ARCH}"
        echo "Version: ${VERSION}"
        echo "Installed-Size: $(du -ks "${INSTALL_DIR}/debian/usr/" | cut -f 1)"

        echo "Package: KOReader"
        echo "Maintainer: KOReader team"
        echo "Homepage: https://koreader.rocks"
        echo "Description: An ebook reader application supporting PDF, DjVu, EPUB, FB2 and many more formats"

    } >"${INSTALL_DIR}/debian/DEBIAN/control"

    (cd "${INSTALL_DIR}/.." \
        && fakeroot dpkg-deb -b "${INSTALL_DIR}/debian" "koreader-${VERSION}-${ARCH}.deb")
else
    echo "${COMMAND} not found, unable to build Debian package"
    exit 1
fi

exit 0

