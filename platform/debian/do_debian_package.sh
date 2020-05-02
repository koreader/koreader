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
        echo "Depends: libsdl2-2.0-0, libc6 (>= 2.2.3)"
        echo "Architecture: ${ARCH}"
        echo "Version: ${VERSION}"
        echo "Installed-Size: $(du -ks "${INSTALL_DIR}/debian/usr/" | cut -f 1)"
        echo "Package: KOReader"
        echo "Maintainer: KOReader team"
        echo "Homepage: https://koreader.rocks"
        echo "Description: Ebook reader application supporting PDF, DjVu, EPUB, FB2 and many more formats"
        echo " KOReader is a document viewer application, originally created for"
        echo " Kindle e-ink readers. It currently runs on Kindle, Kobo, PocketBook,"
        echo " Ubuntu Touch, Android and Linux devices"

    } >"${INSTALL_DIR}/debian/DEBIAN/control"

    ### fix permissions begins
    pushd "${INSTALL_DIR}/debian/usr"

    # remove executable bit from some cr3 files
    find lib/koreader/data/devices -type f -print0 | xargs -0 chmod 644

    # remove luarocks binaries and tests, fix permission for manifests
    find lib/koreader/rocks/lib -type f -name "discovery2spore" -print0 | xargs -0 rm -rfv
    find lib/koreader/rocks/lib -type f -name "wadl2spore" -print0 | xargs -0 rm -rfv
    find lib/koreader/rocks/lib -type d -name "test" -print0 | xargs -0 rm -rfv
    find . -type f -name "rock_manifest" -print0 | xargs -0 chmod 644
    find . -type f -name "manifest" -print0 | xargs -0 chmod 644

    # directories
    find . -type d -print0 | xargs -0 chmod 755

    # executables
    find . -executable -type f -print0 | xargs -0 chmod 755

    # scripts
    find lib/koreader/frontend -type f -name "*.lua" -print0 | xargs -0 chmod 644
    find lib/koreader/plugins -type f -name "*.lua" -print0 | xargs -0 chmod 644
    find lib/koreader/tools -type f -name "*.lua" -print0 | xargs -0 chmod 644
    find lib/koreader/ffi -type f -name "*.lua" -print0 | xargs -0 chmod 644
    find lib/koreader/jit -type f -name "*.lua" -print0 | xargs -0 chmod 644

    # shared libraries
    find lib/koreader/libs -type f -print0 | xargs -0 chmod 644
    find lib/koreader/common -type f -print0 | xargs -0 chmod 644

    # translations
    find . -type f -name "*.po*" -print0 | xargs -0 chmod 644

    # misc
    find . -type f -name "*.html" -print0 | xargs -0 chmod 644
    find . -type f -name "*.pattern" -print0 | xargs -0 chmod 644
    find . -type f -name "*.png" -print0 | xargs -0 chmod 644
    find . -type f -name "git-rev" -print0 | xargs -0 chmod 644
    find . -type f -name "re.lua" -print0 | xargs -0 chmod 644
    find . -type f -name "defaults.lua" -print0 | xargs -0 chmod 644
    find . -type f -name ".gitignore" -print0 | xargs -0 rm -rfv

    popd
    ### fix permission ends

    (cd "${INSTALL_DIR}/.." &&
        fakeroot dpkg-deb -b "${INSTALL_DIR}/debian" "koreader-${VERSION}-${ARCH}.deb")
else
    echo "${COMMAND} not found, unable to build Debian package"
    exit 1
fi

exit 0
