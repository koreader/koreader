#!/bin/bash
# Script to generate mac application bundles for KOReader
# shellcheck disable=SC2164

if [ -z "${1}" ]; then
    echo "${0}: can't find KOReader build, please specify a path"
    exit 1
else
    INSTALL_DIR="${1}"
    VERSION="$(cut -f2 -dv "${1}/koreader/git-rev" | cut -f1,2 -d-)"
fi

{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0">'
    echo '<dict>'
    echo '    <key>CFBundleGetInfoString</key>'
    echo '    <string>KOReader</string>'
    echo '    <key>CFBundleExecutable</key>'
    echo '    <string>koreader</string>'
    echo '    <key>CFBundleIdentifier</key>'
    echo '    <string>koreader.rocks</string>'
    echo '    <key>CFBundleName</key>'
    echo '    <string>KOReader</string>'
    echo '    <key>CFBundleShortVersionString</key>'
    echo "    <string>${VERSION}</string>"
    echo '    <key>CFBundleInfoDictionaryVersion</key>'
    echo '    <string>6.0</string>'
    echo '    <key>CFBundlePackageType</key>'
    echo '    <string>APPL</string>'
    echo '    <key>CFBundleIconFile</key>'
    echo '    <string>koreader</string>'
    echo '</dict>'
    echo '</plist>'
} >"${INSTALL_DIR}/bundle/Contents/Info.plist"

mv -v ${INSTALL_DIR}/bundle ${INSTALL_DIR}/../KOReader-mac-${VERSION}.app

exit 0
