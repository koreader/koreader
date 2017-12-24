[![Build Status][circleci-badge]][circleci-link]
[![Coverage Status][coverage-badge]][coverage-link]
[![AGPL Licence][licence-badge]](COPYING)
KOReader
========

[![Join the chat][gitter-badge]][gitter-link]

KOReader is a document viewer application, originally created for Kindle
e-ink readers. It currently runs on Kindle, Kobo, PocketBook, Ubuntu Touch
and Android devices. Developers can also run a KOReader emulator
for development purposes on desktop PCs with Linux, Windows and 
Mac OSX.

Main features for users
-----------------------

* supports multi-format documents including:
  * paged fixed-layout formats: PDF, DjVu, CBT, and CBZ
  * reflowable e-book formats: ePub, fb2, mobi, doc, chm and plain text
  * scanned PDF/DjVu documents can also be reflowed with built-in K2pdfopt
* use StarDict dictionaries / Wikipedia to lookup words
* highlights can be exported to Evernote cloud account
* highly customizable reader view and typesetting
  * setting arbitrary page margins / line space
  * choosing external fonts and styles
  * built-in multi-lingual hyphenation dictionaries
* supports adding custom online OPDS catalogs
* calibre integration
  * search calibre metadata on your koreader device
  * send ebooks from calibre library to your koreader device wirelessly
  * browser calibre library and download ebooks via calibre OPDS server
* can share ebooks with other koreader devices wirelessly
* various optimizations for e-ink devices
  * paginated menus without animation
  * adjustable text contrast
* multi-lingual user interface
* online Over-The-Air software update

Highlights for developers
--------------------------

* frontend written in Lua scripting language
  * multi-platform support through a single code-base
  * you can help develop KOReader in any editor without compilation
  * high runtime efficiency through LuaJIT acceleration
  * light-weight self-contained widget toolkit with small memory footprint
  * extensible with plugin system
* interfaced backends for documents parsing and rendering
  * high quality document backend libraries like MuPDF, DjvuLibre and CREngine
  * interacting with frontend via LuaJIT FFI for best performence
* in active development
  * with contributions from developers around the world
  * continuous integration with CircleCI
  * with unit tests (busted), static code analysis (luacheck) and code coverage test (luacov/coveralls)
  * automated nightly builds available at http://build.koreader.rocks/download/nightly/
* free as in free speech
  * licensed under Affero GPL v3
  * all dependencies are free software

Check out the [KOReader wiki](https://github.com/koreader/koreader/wiki) to learn
more about this project.

Building Prerequisites
======================

These instructions for how to get and compile the source are intended for a Linux
OS. Windows users are suggested to develop in a [Linux VM][linux-vm] or use Wubi.

To get and compile the source you must have `patch`, `wget`, `unzip`, `git`,
`cmake` and `luarocks` installed, as well as a version of `autoconf`
greater than 2.64. You also need `nasm` and of course a compiler like `gcc`
or `clang`. If you want to cross-compile for other architectures, you need a proper
cross-compile toolchain. Your GCC should be at least version 4.8.

Users of Debian and Ubuntu can install the required packages using:
```
sudo apt-get install build-essential git patch wget unzip \
gettext autoconf automake cmake libtool nasm luarocks \
libssl-dev libffi-dev libsdl2-dev libc6-dev-i386 xutils-dev linux-libc-dev:i386 zlib1g:i386
```

If you are running Fedora, be sure to install the package `libstdc++-static`.

That's all you need to get the emulator up and running with `./kodev build` and `./kodev run`.

Cross compile toolchains are available for Ubuntu users through these commands:
```
# for Kindle
sudo apt-get install gcc-arm-linux-gnueabi g++-arm-linux-gnueabi
# for Kobo and Ubuntu touch
sudo apt-get install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
# for Win32
sudo apt-get install gcc-mingw-w64-i686 g++-mingw-w64-i686
```

The packages `pkg-config-arm-linux-gnueabihf` and `pkg-config-arm-linux-gnueabi` may
block you from building for Kobo or Kindle. Remove them if you get an ld error,
`/usr/lib/gcc-cross/arm-linux-gnueabihf/4.8/../../../../arm-linux-gnueabihf/bin/
ld: cannot find -lglib-2.0`

Mac OSX users may need to install these tools:
```
brew install nasm binutils libtool autoconf automake cmake makedepend sdl2 lua51 gettext
echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> ~/.bash_profile
```

The KOReader Android build requires `ant`, `openjdk-8-jdk` and `p7zip-full`. A compatible version of the Android NDK and SDK will be downloaded automatically by `./kodev build android` if no NDK or SDK is provided in environment variables. For that purpose you can use `NDK=/ndk/location SDK=/sdk/location ./kodev build android`.

Users of Debian Jessie first need to configure the `backports` repository:
```
sudo echo "deb http://ftp.debian.org/debian jessie-backports main" > /etc/apt/sources.list.d/backports.list
sudo apt-get update
```
For both Ubuntu and Debian, install the packages:
```
sudo apt-get install ant openjdk-8-jdk
```
Users on Debian finally need to remove JRE version 7:
```
sudo apt-get remove openjdk-7-jre-headless
```

In order to build KOReader package for Ubuntu Touch, the `click` package management
tool is needed, Ubuntu users can install it with:
```
sudo apt-get install click
```

You might also need SDL library packages if you want to compile and run
KOReader on Linux PC. Fedora users can install `SDL` and `SDL-devel` package.
Ubuntu users probably need to install the `libsdl2-dev` package:

Getting the source
==================

```
git clone https://github.com/koreader/koreader.git
cd koreader && ./kodev fetch-thirdparty
```

Building, Running and Testing
=============================

For emulating KOReader on Linux, Windows and Mac OSX
-------------

To build an emulator on your current Linux or OSX machine:
```
./kodev build
```

If you want to compile the emulator for Windows run:
```
./kodev build win32
```

To run KOReader on your development machine:
```
./kodev run
```

To automatically set up a number of primarily luarocks-related environment variables:
```
./kodev activate
```

To run unit tests:
```
./kodev test base
./kodev test front
```

To run a specific unit test (for test development):
```
./kodev test front readerbookmark_spec.lua
```

NOTE: Extra dependencies for tests: `busted` and `ansicolors` from luarocks.

To run Lua static analysis:
```
make static-check
```

NOTE: Extra dependencies for tests: `luacheck` from luarocks

You may need to checkout the [circleci config file][circleci-conf] to setup up
a proper testing environment. Briefly, you need to install `luarocks` and
then install `busted` with `luarocks`. The "eng" language data file for
tesseract-ocr is also need to test OCR functionality. Finally, make sure
that `luajit` in your system is at least of version 2.0.2.

You can also specify the size and DPI of the emulator's screen using
`-w=X` (width), `-h=X` (height), and `-d=X` (DPI). There is also a convenience
`-s` (simulate) flag with some presets like `kobo-aura-one`, `kindle3`, and
`hidpi`. The latter is a fictional device with `--screen_width=1500`,
`--screen_height=2000` and `--screen_dpi=600` to help ensure DPI scaling works correctly.
Sample usage:
```
./kodev run -s=kobo-aura-one
```

To use your own koreader-base repo instead of the default one change the `KOR_BASE`
environment variable:
```
make KOR_BASE=../koreader-base
```

This will be handy if you are developing `koreader-base` and you want to test your
modifications with the KOReader frontend. NOTE: this only supports relative path for now.

For EReader devices (kindle, kobo, pocketbook, ubuntu-touch)
---------------------

To build an installable package for Kindle:
```
./kodev release kindle
```

To build an installable package for Kobo:
```
./kodev release kobo
```

To build an installable package for PocketBook:
```
./kodev release pocketbook
```

To build an installable package for Ubuntu Touch
```
./kodev release ubuntu-touch
```

You may checkout our [nightlybuild script][nb-script] to see how to build a
package from scratch.

For Android devices
-------------------

A compatible version of the Android NDK and SDK will be downloaded automatically by the
`kodev` command. If you already have an Android NDK and SDK installed that you would like
to use instead, make sure that the `android` and `ndk-build` tools can be found in your
`PATH` environment variable. Additionally, the `NDK` and `SDK` variables should point
to the root directory of the Android NDK and SDK respectively.

Then, run this command to build an installable package for Android:
```
./kodev release android
```

Translation
===========

Please refer to [l10n's README][l10n-readme] to grab the latest translations
from [the KOReader project on Transifex][koreader-transifex] with this command:
```
make po
```
If your language is not listed on the Transifex project, please don't hesitate
to send a language request [here][koreader-transifex].

Variables in translation
-------

Some strings contain variables that should remain unaltered in translation.
For example:

```lua
The title of the book is %1 and its author is %2.
```
This might be displayed as:
```lua
The title of the book is The Republic and its author is Plato.
```
To aid localization the variables may be freely positioned:
```lua
De auteur van het boek is %2 en de titel is %1.
```
That would result in:
```lua
De auteur van het boek is Plato en de titel is The Republic.
```

Use ccache
==========

Ccache can speed up recompilation by caching previous compilations and detecting
when the same compilation is being repeated. In other words, it will decrease
build time when the sources have been built before. Ccache support has been added to
KOReader's build system. To install ccache:

* in Ubuntu use:`sudo apt-get install ccache`
* in Fedora use:`sudo yum install ccache`
* from source:
  * download the latest ccache source from http://ccache.samba.org/download.html
  * extract the source package in a directory
  * `cd` to that directory and use:`./configure && make && sudo make install`
* to disable ccache, use `export USE_NO_CCACHE=1` before make.
* for more information about ccache, visit: https://ccache.samba.org/


[base-readme]:https://github.com/koreader/koreader-base/blob/master/README.md
[nb-script]:https://gitlab.com/koreader/nightly-builds/blob/master/build_release.sh
[circleci-badge]:https://circleci.com/gh/koreader/koreader.svg?style=shield
[circleci-link]:https://circleci.com/gh/koreader/koreader
[circleci-conf]:https://github.com/koreader/koreader-base/blob/master/.circleci/config.yml
[linux-vm]:http://www.howtogeek.com/howto/11287/how-to-run-ubuntu-in-windows-7-with-vmware-player/
[l10n-readme]:https://github.com/koreader/koreader/blob/master/l10n/README.md
[koreader-transifex]:https://www.transifex.com/projects/p/koreader/
[coverage-badge]:https://codecov.io/gh/koreader/koreader/branch/master/graph/badge.svg
[coverage-link]:https://codecov.io/gh/koreader/koreader
[licence-badge]:http://img.shields.io/badge/licence-AGPL-brightgreen.svg
[gitter-badge]:https://badges.gitter.im/Join%20Chat.svg
[gitter-link]:https://gitter.im/koreader/koreader?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge
