#!/bin/bash
# Script to generate mac application bundles for KOReader
#
# We don't use XCode at all. Just commandline tools.
#
# menu.xml contains the main menu of a typical OSX program.
# each time some user facing string in menu.xml changed we can
# generate a new translation template with:
#
#  cp menu.xml menu.xib
#  ibtool --generate-strings-file mac.strings menu.xib
#  rm -rf menu.xib
#
# the generated "mac.strings" is in xliff format (binary, not plain text)
# and can be translated using an xliff editor or an online service that support
# IOS string format, like weblate.

COPYRIGHT="Copyright © $(date +"%Y") KOReader"

command_exists() {
    type "$1" >/dev/null 2>/dev/null
}

if [ -z "${1}" ]; then
    echo "${0}: can't find KOReader build, please specify a path"
    exit 1
else
    VERSION="$(cut -f2 -dv "${1}/koreader/git-rev" | cut -f1,2 -d-)"
    APP_PATH="${1}/bundle"
    APP_BUNDLE="${1}/../KOReader"
    OSX_MAJOR=$(sw_vers -productVersion | cut -d "." -f1)
    OSX_MINOR=$(sw_vers -productVersion | cut -d "." -f2)
fi

# minimum deployment target based on host version
if [ -z "${MACOSX_DEPLOYMENT_TARGET}" ]; then
    if [ "${OSX_MAJOR}" == 11 ]; then
        MACOSX_DEPLOYMENT_TARGET=10.14
    elif [ "${OSX_MAJOR}" == 10 ]; then
        MACOSX_DEPLOYMENT_TARGET="10.$((OSX_MINOR - 2))"
    fi
fi

# Generate PkgInfo and Info.plist
printf "APPL????" >"${APP_PATH}/Contents/PkgInfo"
cat <<END >"${APP_PATH}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>English</string>
        <key>CFBundleName</key>
        <string>KOReader</string>
        <key>CFBundleDisplayName</key>
        <string>KOReader</string>
        <key>CFBundleExecutable</key>
        <string>koreader</string>
        <key>CFBundleIconFile</key>
        <string>icon.icns</string>
        <key>CFBundleIdentifier</key>
        <string>rocks.koreader</string>
        <key>CFBundleShortVersionString</key>
        <string>${VERSION}</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleSignature</key>
        <string>????</string>
        <key>CFBundleVersion</key>
        <string>1.0</string>
        <key>CFBundleDocumentTypes</key>
        <array>
            <dict>
                <key>CFBundleTypeExtensions</key>
                <array>
                    <string>azw</string>
                    <string>cbz</string>
                    <string>chm</string>
                    <string>djv</string>
                    <string>djvu</string>
                    <string>doc</string>
                    <string>docx</string>
                    <string>epub</string>
                    <string>fb2</string>
                    <string>htm</string>
                    <string>html</string>
                    <string>md</string>
                    <string>mobi</string>
                    <string>pdb</string>
                    <string>pdf</string>
                    <string>prc</string>
                    <string>rtf</string>
                    <string>txt</string>
                    <string>xhtml</string>
                    <string>xps</string>
                </array>
                <key>CFBundleTypeIconFile</key>
                <string>icon</string>
                <key>CFBundleTypeName</key>
                <string>docs</string>
                <key>CFBundleTypeRole</key>
                <string>Viewer</string>
            </dict>
        </array>
        <key>NSHumanReadableCopyright</key>
        <string>${COPYRIGHT}</string>
        <key>NSHighResolutionCapable</key>
        <true/>
        <key>NSPrincipalClass</key>
        <string>NSApplication</string>
        <key>NSMainNibFile</key>
        <string>MainMenu</string>
        <key>LSMultipleInstancesProhibited</key>
        <true/>
        <key>LSMinimumSystemVersion</key>
        <string>${MACOSX_DEPLOYMENT_TARGET}</string>
        <key>SDL_FILESYSTEM_BASE_DIR_TYPE</key>
        <string>bundle</string>
    </dict>
</plist>
END

# freeze shared libraries, so they can be loaded within the application bundle
pushd "${APP_PATH}/Contents/koreader" || exit 1
for dir in common libs; do
    path=$(basename "${dir}")
    pushd "${dir}" || exit 1
    for library in *.so *.dylib; do
        install_name_tool -id "${library}" "$(basename "${library}")"
        # there may be more than one dependency to fix, so get all of them and iterate
        dependencies=$(otool -L "${library}" | grep "Users.*x86_64" | tr -s " " | cut -f1 -d" ")
        if [ -n "${dependencies}" ]; then
            for dependency in ${dependencies}; do
                filename=$(basename "${dependency}")
                if [ ! "${library}" = "${filename}" ]; then
                    install_name_tool -change "${dependency}" "${path}/${filename}" "${library}"
                fi
            done
        fi
    done
    popd || exit 1
done

# Brew has a tendency to infiltrate our builds and take over some of the dependencies...
BREW="$(brew --prefix)/opt"
# So, because it made us pick those up, ship 'em
cp "${BREW}/gettext/lib/libintl.8.dylib" "${BREW}/webp/lib/libwebp.7.dylib" "${BREW}/libsodium/lib/libsodium.23.dylib" libs
chmod 777 libs/libintl.8.dylib libs/libwebp.7.dylib libs/libsodium.23.dylib
# Update their name
install_name_tool -id libintl.8.dylib libs/libintl.8.dylib
install_name_tool -id libwebp.7.dylib libs/libwebp.7.dylib
install_name_tool -id libsodium.23.dylib libs/libsodium.23.dylib
# And make sure anything that depends on them points to ours
install_name_tool -change "${BREW}/gettext/lib/libintl.8.dylib" libs/libintl.8.dylib libs/libglib-2.0.dylib
install_name_tool -change "${BREW}/webp/lib/libwebp.7.dylib" libs/libwebp.7.dylib libs/liblept.5.dylib
install_name_tool -change "${BREW}/webp/lib/libwebp.7.dylib" libs/libwebp.7.dylib libs/libtesseract.3.dylib
install_name_tool -change "${BREW}/libsodium/lib/libsodium.23.dylib" libs/libsodium.23.dylib libs/libczmq.1.dylib
install_name_tool -change "${BREW}/libsodium/lib/libsodium.23.dylib" libs/libsodium.23.dylib libs/libfmq.1.dylib
install_name_tool -change "${BREW}/libsodium/lib/libsodium.23.dylib" libs/libsodium.23.dylib libs/libzmq.4.dylib
install_name_tool -change "${BREW}/libsodium/lib/libsodium.23.dylib" libs/libsodium.23.dylib libs/libzyre.1.dylib

# prepare bundle for distribution
ln -s /usr/bin/tar tar
mv COPYING README.md ../Resources/
mv koreader ../MacOS/koreader
rm -rf cache clipboard history ota \
    l10n/.git l10n/.tx l10n/templates l10n/LICENSE l10n/Makefile l10n/README.md \
    plugins/SSH.koplugin plugins/hello.koplugin plugins/timesync.koplugin \
    plugins/autofrontlight.koplugin resources/fonts resources/icons/src \
    rocks/bin rocks/lib/luarocks screenshots spec tools

# adjust reader.lua a bit.

sed '1d' reader.lua >tempfile
sed -i.backup 's/.\/reader.lua/koreader/' tempfile
mv tempfile reader.lua
rm -f tempfile*
chmod -x reader.lua
popd || exit 1

# bundle translations, if any
for path in l10n/*; do
    lang=$(echo "${path}" | sed s'/l10n\///')
    if [ "${lang}" != "templates" ]; then
        translation_file="l10n/${lang}/mac.strings"
        if [ -f "${translation_file}" ]; then
            mkdir -p "${APP_PATH}/Contents/Resources/${lang}.lproj"
            cp -pv "${translation_file}" "${APP_PATH}/Contents/Resources/${lang}.lproj/MainMenu.strings"
        fi
    fi
done

mv "${APP_PATH}" "${APP_BUNDLE}.app"

# package as 7z reduces size from 80MB to 30MB
if command_exists "7z"; then
    7z a -l -m0=lzma2 -mx=9 "${APP_BUNDLE}-${VERSION}.7z" "${APP_BUNDLE}.app"
    rm -rfv "${APP_BUNDLE}.app"
fi
