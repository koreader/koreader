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
if command_exists "${COMMAND}"; then
    mkdir -p "${INSTALL_DIR}/debian/DEBIAN"
    {
        echo "Section: graphics"
        echo "Priority: optional"
        echo "Depends: libsdl2-2.0-0, libc6 (>= 2.2.1)"
        echo "Architecture: ${ARCH}"
        echo "Version: ${VERSION}"
        echo "Installed-Size: $(du -ks "${INSTALL_DIR}/debian/usr/" | cut -f 1)"

        echo "Package: koreader"
        echo "Maintainer: KOReader team <dummy@koreader.rocks>"
        echo "Homepage: https://koreader.rocks"
        echo "Description: Ebook reader application supporting PDF, DjVu, EPUB, FB2 and many more formats"
        echo " KOReader is a document viewer application, originally created for Kindle e-ink readers."
        echo " It currently runs on Kindle, Kobo, PocketBook, Ubuntu Touch, Android and Linux devices"

    } >"${INSTALL_DIR}/debian/DEBIAN/control"

    # remove executable bit from some cr3 files
    (cd "${INSTALL_DIR}/debian/usr/lib/koreader/data/devices" &&
        find . -type f -print0 | xargs -0 chmod 644)

    # fix permissions for executables
    (cd "${INSTALL_DIR}/debian/usr" &&
        find . -executable -type f -print0 | xargs -0 chmod 755)

    # fix permissions for shared libraries
    (cd "${INSTALL_DIR}/debian/usr/lib/koreader/libs" &&
        find . -type f -print0 | xargs -0 chmod 644)

    # fix permissions for directories
    (cd "${INSTALL_DIR}/debian/usr" &&
        find . -type d -print0 | xargs -0 chmod 755)

    # remove luarocks binaries and tests
    (cd "${INSTALL_DIR}/debian/usr/lib/koreader/rocks/lib/luarocks" &&
        find . -type f -name "discovery2spore" -print0 | xargs -0 rm -rfv &&
        find . -type f -name "wadl2spore" -print0 | xargs -0 rm -rfv &&
        find . -type d -name "test" -print0 | xargs -0 rm -rfv)

    (cd "${INSTALL_DIR}/.." &&
        fakeroot dpkg-deb -b "${INSTALL_DIR}/debian" "koreader-${VERSION}-${ARCH}.deb")
else
    echo "${COMMAND} not found, unable to build Debian package"
    exit 1
fi

exit 0
