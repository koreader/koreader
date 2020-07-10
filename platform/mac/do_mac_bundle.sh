#!/bin/bash
# Script to generate mac application bundles for KOReader

command_exists() {
    type "$1" >/dev/null 2>/dev/null
}

if [ -z "${1}" ]; then
    echo "${0}: can't find KOReader build, please specify a path"
    exit 1
else
    INSTALL_DIR="${1}"
    VERSION="$(cut -f2 -dv "${1}/koreader/git-rev" | cut -f1,2 -d-)"
fi

cat <<EOF >"${INSTALL_DIR}/bundle/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>CFBundleGetInfoString</key>
        <string>KOReader</string>
        <key>CFBundleExecutable</key>
        <string>koreader</string>
        <key>CFBundleIdentifier</key>
        <string>koreader.rocks</string>
        <key>CFBundleName</key>
        <string>KOReader</string>
        <key>CFBundleShortVersionString</key>
        <string>${VERSION}</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleIconFile</key>
        <string>icon</string>
    </dict>
</plist>
EOF

APP_PATH="${INSTALL_DIR}/bundle"
APP_BUNDLE="${INSTALL_DIR}/../KOReader"

# Use otool to change rpath of libraries.
# Along with libs, serialize.so in common also needs to be fixed
pushd "${INSTALL_DIR}/bundle/Contents/Resources/koreader" || exit 1
for directory in common libs; do
    directoryName=$(basename "${directory}")
    echo "Checking ${directory}"
    pushd "${directory}" || exit 1
    for libToCheck in *.so *.dylib; do
        # there may be more than one library to fix, so get all of them and iterate
        libsToChange=$(otool -L "${libToCheck}" | grep "Users.*x86_64" | tr -s " " | cut -f1 -d" ")
        if [ -z "${libsToChange}" ]; then
            echo "Nothing to do, skipping ${libToCheck}"
        else
            for libToChange in ${libsToChange}; do
                fileNameOfLibToChange=$(basename "${libToChange}")
                if [ "${libToCheck}" = "${fileNameOfLibToChange}" ]; then
                    echo "Skipping recursive ${libToChange} ${libToCheck}"
                else
                    echo "Fixing ${libToCheck} ${libToChange}"
                    install_name_tool -change "${libToChange}" "${directoryName}/${fileNameOfLibToChange}" "${libToCheck}"
                fi
            done
        fi
    done
    popd || exit 1
done
popd || exit 1

# remove things from the bundle
rm -rf \
    "${APP_PATH}/Contents/Resources/koreader/cache" \
    "${APP_PATH}/Contents/Resources/koreader/clipboard" \
    "${APP_PATH}/Contents/Resources/koreader/history" \
    "${APP_PATH}/Contents/Resources/koreader/ota" \
    "${APP_PATH}/Contents/Resources/koreader/resources/fonts" \
    "${APP_PATH}/Contents/Resources/koreader/resources/icons/src" \
    "${APP_PATH}/Contents/Resources/koreader/resources/kobo-touch.probe.png" \
    "${APP_PATH}/Contents/Resources/koreader/resources/koreader.icns" \
    "${APP_PATH}/Contents/Resources/koreader/rocks/bin" \
    "${APP_PATH}/Contents/Resources/koreader/rocks/lib/luarocks" \
    "${APP_PATH}/Contents/Resources/koreader/screenshots" \
    "${APP_PATH}/Contents/Resources/koreader/spec" \
    "${APP_PATH}/Contents/Resources/koreader/tools" \
    "${APP_PATH}/Contents/Resources/koreader/README.md"

mv \
    "${APP_PATH}/Contents/Resources/koreader/COPYING" \
    "${APP_PATH}/Contents/Resources/COPYING"

ln -s /usr/bin/tar "${APP_PATH}/Contents/Resources/koreader/tar"

# package as DMG if create-dmg is available
# reduces size from 80MB to 40MB
mv "${APP_PATH}" "${APP_BUNDLE}.app"
if command_exists "create-dmg"; then
    # create KOReader-$VERSION.dmg with KOReader.app inside
    create-dmg "${APP_BUNDLE}.app" --overwrite
    # create-dmg fails because we omit codesign
    exit 0
else
    # rename as KOReader-$VERSION.app
    mv -v "${APP_BUNDLE}.app" "${APP_BUNDLE}-${VERSION}.app"
fi
