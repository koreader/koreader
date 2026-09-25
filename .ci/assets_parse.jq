def asset_parse:
  . as $file
  | {
    # Android
    "android": "Android ARM",
    "android-arm": "Android ARM",
    "android-arm64": "Android ARM64",
    "android-fdroid": "Android F-Droid",
    "android-x86": "Android x86",
    "android-x86_64": "Android x86_64",
    # Cervantes
    "cervantes": "Cervantes",
    # Kindle
    "kindle": "Kindle",
    "kindle-legacy": "Kindle Legacy",
    "kindlehf": "Kindle HF",
    "kindlepw2": "Kindle PW2",
    # Kobo
    "kobo": "Kobo",
    "kobov5": "Kobo v5",
    # Linux
    "appimage-aarch64": "Linux ARM64",
    "appimage-armhf": "Linux ARMhf",
    "appimage-x86_64": "Linux x86_64",
    "debian-amd64": "Linux x86_64",
    "debian-arm64": "Linux ARM64",
    "debian-armhf": "Linux ARMhf",
    "linux-aarch64": "Linux ARM64",
    "linux-amd64": "Linux x86_64",
    "linux-arm": "Linux ARMhf",
    "linux-arm64": "Linux ARM64",
    "linux-armhf": "Linux ARMhf",
    "linux-armv7l": "Linux ARMhf",
    "linux-x86_64": "Linux x86_64",
    # macOS
    "macos-10.15-x86_64": "macOS x86_64",
    "macos-11.0-arm64": "macOS ARM64",
    # PocketBook
    "pocketbook": "PocketBook",
    "pocketbookhf": "PocketBook HF",
    # reMarkable
    "remarkable": "reMarkable",
    "remarkable-aarch64": "reMarkable Pro",
  } as $platform_name
  | {
    # Android
    "android-arm": "apk link",
    "android-arm64": "apk link",
    "android-x86": "apk link",
    "android-x86_64": "apk link",
    # Linux
    "appimage-aarch64": "AppImage link",
    "appimage-armhf": "AppImage link",
    "appimage-x86_64": "AppImage link",
    "debian-amd64": "deb link",
    "debian-arm64": "deb link",
    "debian-armhf": "deb link",
    "linux-aarch64": "tar.xz link",
    "linux-arm": "tar.xz link",
    "linux-x86_64": "tar.xz link",
  } as $link_type
  | "(?<platform>.+)" as $platform_rx
  | "(?<version>(?<base_version>[0-9]+(\\.[0-9]+)*)(-(?<commit_number>[0-9]+)-g(?<commit_hash>[a-f0-9]+))?(_[0-9]{4}-[0-9]{2}-[0-9]{2})?)" as $version_rx
  | "\\.(?<extension>(7z|apk|AppImage|deb|kotasync|targz|tar\\.xz|zip|zsync))$" as $extension_rx
  | $file | (
    # koreader-linux-x86_64-v2023.06.1.tar.xz
    # koreader-android-arm-v2015.11-654-gb7392f7_2018-03-09.apk
    capture("/?koreader-" + $platform_rx + "-v" + $version_rx + $extension_rx)
    # koreader-v2023.06.1-x86_64.AppImage
    # koreader-v2025.10-197-g7c5ee9c1a2_2026-03-13-x86_64.AppImage
    // (
         capture("/?koreader-v" + $version_rx + "-" + $platform_rx + $extension_rx)
         | .platform = "linux-" + .platform
    )
    # koreader_2026.09-8-g84cf973-1_amd64.deb
    // (
         capture("/?koreader_" + $version_rx + "-1_" + $platform_rx + $extension_rx)
         | .platform = "linux-" + .platform
    )
    # koreader-android-arm-latest-nightly
    # koreader-kindlepw2-latest-nightly.kotasync
    # koreader-kindlepw2-latest-stable.zsync
    // (
      capture("/?koreader-" + $platform_rx + "-latest-(?<version>nightly|stable)(" + $extension_rx + "|$)")
      | .base_version = .version
      | .sort_version = [666]
      | .extension //= ($link_type[.platform] // "link")
      | .latest = true
      | .ota = true
      | .stable = .base_version == "stable"
    )
    # koreader-android-fdroid-latest
    // (
      capture("/?koreader-android-fdroid-latest$")
      | .platform = "android-fdroid"
      | .base_version = "stable"
      | .sort_version = [666]
      | .extension = "metadata"
      | .latest = true
      | .ota = true
      | .stable = true
    )
    // error("unsupported asset: " + .)
  ) #| debug
  # Finalize.
  | .file = $file
  | .platform_name = ($platform_name[.platform] // error("invalid platform: " + .platform + ", " + (. | tostring)))
  | .sort_version = (.sort_version // [
    (.base_version | split(".") | map(tonumber)),
    (.commit_number // 0 | tonumber)
  ])
  | .stable = (.stable // if .commit_number then false else true end)
  | .ota = (.ota or .extension == "kotasync" or .extension == "zsync")
 #| debug
;

# vim: sw=2
