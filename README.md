[![KOReader](https://raw.githubusercontent.com/koreader/koreader.github.io/master/koreader-logo.png)](https://koreader.rocks)

#### KOReader is a document viewer primarily aimed at e-ink readers.

[![AGPL Licence][badge-license]](COPYING)
[![Latest release][badge-release]][link-gh-releases]
[![Gitter][badge-gitter]][link-gitter]
[![Mobileread][badge-mobileread]][link-forum]
[![Build Status][badge-circleci]][link-circleci]
[![Coverage Status][badge-coverage]][link-coverage]
[![Weblate Status][badge-weblate]][link-weblate]

[Download](https://github.com/koreader/koreader/releases) •
[Wiki](https://github.com/koreader/koreader/wiki) •
[Developer docs](http://koreader.rocks/doc/)

## Main features

* **portable**: runs on embedded devices (Cervantes, Kindle, Kobo, PocketBook, reMarkable), Android and Linux computers. Developers can run a KOReader emulator in Linux and MacOS.

* **multi-format documents**: supports fixed page formats (PDF, DjVu, CBT, CBZ) and reflowable e-book formats (EPUB, FB2, Mobi, DOC, CHM, TXT). Scanned PDF/DjVu documents can also be reflowed with the built-in K2pdfopt library.

* **full-featured reading**: multi-lingual user interface with a highly customizable reader view and many typesetting options. You can set arbitrary page margins, override line spacing and choose external fonts and styles. It has multi-lingual hyphenation dictionaries bundled into the application.

* **integrated** with *calibre* (search metadata, receive ebooks wirelessly, browse library via OPDS),  *Evernote* (export hightlights), *Wallabag*, *Wikipedia*, *Google Translate* and other content providers.

* **optimized for e-ink devices**: custom UI without animation, with paginated menus, adjustable text contrast, and easy zoom to fit content or page in paged media.

* **extensible**: via plugins

* **and much more**: look up words with StarDict dictionaries / Wikipedia, add your own online OPDS catalogs and RSS feeds, share ebooks with other KOReader devices wirelessly, online over-the-air software updates, an FTP client, an SSH server, …

Please check the [wiki][link-wiki] to discover more features and to help us document them.

## Screenshots

<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-menu.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-menu-thumbnail.png" alt="" width="200px"></a>
<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-footnotes.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-footnotes-thumbnail.png" alt="" width="200px"></a>
<a href="https://github.com/koreader/koreader-artwork/raw/master/koreader-dictionary.png"><img src="https://github.com/koreader/koreader-artwork/raw/master/koreader-dictionary-thumbnail.png" alt="" width="200px"></a>

## Installation

Please follow the model specific steps for your device:

[Android](https://github.com/koreader/koreader/wiki/Installation-on-Android-devices) •
[Cervantes](https://github.com/koreader/koreader/wiki/Installation-on-BQ-devices) •
[Kindle](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices) •
[Kobo](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices) •
[Linux](https://github.com/koreader/koreader/wiki/Installation-on-desktop-linux) •
[Pocketbook](https://github.com/koreader/koreader/wiki/Installation-on-PocketBook-devices) •
[reMarkable](https://github.com/koreader/koreader/wiki/Installation-on-Remarkable)


## Development

[Setting up a build environment](doc/Building.md) •
[Collaborating with Git](doc/Collaborating_with_Git.md) •
[Building targets](doc/Building_targets.md) •
[Porting](doc/Porting.md) •
[Developer docs](http://koreader.rocks/doc/)

## Support

KOReader is developed and supported by volunteers all around the world. There are many ways you can help:

- [fix bugs][link-issues-bugs] and [implement new features][link-issues-features]
- [translate the program into your language][link-weblate] or improve an existing translation
- document lesser-known features on the [wiki][link-wiki]
- help others with your knowledge on the [forum][link-forum]

Right now we only support [liberapay](https://liberapay.com/KOReader) donations, but you can also create a [bounty][link-bountysource] to motivate others to work on a specific bug or feature request.

Also if you have and old Pocketbook device you don't want, we might find it useful to tinker a bit with that platform. Please contact us through the forum or GitHub.

## Contributors

[![Last commit][badge-last-commit]][link-gh-commits]
[![Commit activity][badge-commit-activity]][link-gh-insights]

[![0](https://sourcerer.io/fame/Frenzie/koreader/koreader/images/0)](https://sourcerer.io/fame/Frenzie/koreader/koreader/links/0)
[![1](https://sourcerer.io/fame/Frenzie/koreader/koreader/images/1)](https://sourcerer.io/fame/Frenzie/koreader/koreader/links/1)
[![2](https://sourcerer.io/fame/Frenzie/koreader/koreader/images/2)](https://sourcerer.io/fame/Frenzie/koreader/koreader/links/2)
[![3](https://sourcerer.io/fame/Frenzie/koreader/koreader/images/3)](https://sourcerer.io/fame/Frenzie/koreader/koreader/links/3)
[![4](https://sourcerer.io/fame/Frenzie/koreader/koreader/images/4)](https://sourcerer.io/fame/Frenzie/koreader/koreader/links/4)
[![5](https://sourcerer.io/fame/Frenzie/koreader/koreader/images/5)](https://sourcerer.io/fame/Frenzie/koreader/koreader/links/5)
[![6](https://sourcerer.io/fame/Frenzie/koreader/koreader/images/6)](https://sourcerer.io/fame/Frenzie/koreader/koreader/links/6)
[![7](https://sourcerer.io/fame/Frenzie/koreader/koreader/images/7)](https://sourcerer.io/fame/Frenzie/koreader/koreader/links/7)

[badge-bountysource]:https://img.shields.io/bountysource/team/koreader/activity?color=red
[badge-circleci]:https://circleci.com/gh/koreader/koreader.svg?style=shield
[badge-coverage]:https://codecov.io/gh/koreader/koreader/branch/master/graph/badge.svg
[badge-commit-activity]:https://img.shields.io/github/commit-activity/m/koreader/koreader
[badge-gitter]:https://img.shields.io/gitter/room/koreader/koreader?color=red
[badge-last-commit]:https://img.shields.io/github/last-commit/koreader/koreader?color=orange
[badge-license]:https://img.shields.io/github/license/koreader/koreader
[badge-release]:https://img.shields.io/github/release/koreader/koreader.svg
[badge-mobileread]:https://img.shields.io/badge/forum-on_mobileread-lightgrey
[badge-weblate]:https://hosted.weblate.org/widgets/koreader/-/koreader/svg-badge.svg

[link-bountysource]:https://www.bountysource.com/teams/koreader
[link-circleci]:https://circleci.com/gh/koreader/koreader
[link-coverage]:https://codecov.io/gh/koreader/koreader
[link-forum]:http://www.mobileread.com/forums/forumdisplay.php?f=276
[link-gh-commits]:https://github.com/koreader/koreader/commits/master
[link-gh-insights]:https://github.com/koreader/koreader/pulse
[link-gh-releases]:https://github.com/koreader/koreader/releases
[link-gitter]:https://gitter.im/koreader/koreader
[link-issues-bugs]:https://github.com/koreader/koreader/issues?q=is%3Aopen+is%3Aissue+label%3Abug
[link-issues-features]:https://github.com/koreader/koreader/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement
[link-weblate]:https://hosted.weblate.org/engage/koreader/?utm_source=widget
[link-wiki]:https://github.com/koreader/koreader/wiki
