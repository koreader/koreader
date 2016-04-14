[![Build Status][travis-badge]][travis-link]
[![Coverage Status][coverage-badge]][coverage-link]
[![AGPL Licence][licence-badge]](COPYING)
KOReader
========

[![Join the chat][gitter-badge]][gitter-link]

KOReader is a document viewer application, originally created for Kindle
e-ink readers. It currently runs on Kindle, Kobo, PocketBook, Ubuntu Touch
and Android (2.3+) devices. Developers can also run KOReader emulator
for development purpose on desktop PC with Linux and Windows and 
Mac OSX (experimental for now).

Main features for users
-----------------------

* supports multi-format documents including:
  * paged fixed-layout formats: PDF, DjVu and CBZ
  * reflowable e-book formats: ePub, fb2, mobi, doc, chm and plain text
  * scanned PDF/DjVu documents can also be reflowed with built-in K2pdfopt
* use StarDict dictionaries / Wikipedia to lookup words
* highlights can be exported to Evernote cloud account
* highly customizable reader view and typeset
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
  * running on multi-platform with only one code-base maintained
  * developing koreader in any editor without compilation
  * high runtime efficiency by LuaJIT acceleration
  * light-weight self-contained widget toolkit with small memory footprint
  * extensible with plugin system
* interfaced backends for documents parsing and rendering
  * high quality document backend libraries like MuPDF, DjvuLibre and CREngine
  * interacting with frontend via LuaJIT FFI for best performence
* in active development
  * contributed by developers around the world
  * continuous integration with Travis CI
  * with unit tests, static analysis and code coverage test
  * automatic release of nightly builds
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
cross-compile toolchain. Your GCC should be at least of version 4.7 for both native
and cross compiling.

Users of Debian and Ubuntu can install the required packages using:
```
sudo apt-get install build-essential git patch wget unzip \
gettext autoconf cmake libtool nasm luarocks \
libssl-dev libffi-dev libsdl2-dev libc6-dev-i386 linux-libc-dev:i386
```
Note that the `linux-libc-dev:i386` package is only necessary for x86_64 machines.

Cross compile toolchains are available for Ubuntu users through these commands:
```
# for Kindle
sudo apt-get install gcc-arm-linux-gnueabi g++-arm-linux-gnueabi
# for Kobo and Ubuntu touch
sudo apt-get install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
# for Win32
sudo apt-get install gcc-mingw-w64-i686 g++-mingw-w64-i686
```

Mac OSX users may need to install these tools:
```
brew install gcc48 nasm binutils libtool autoconf automake sdl2
```

A recent version of Android SDK/NDK and `ant` are needed in order to build
Koreader for Android devices.
```
sudo apt-get install ant
```

In order to build Koreader package for Ubuntu Touch, the `click` package management
tool is needed, Ubuntu users can install it with:
```
sudo apt-get install click
```

You might also need SDL library packages if you want to compile and run
Koreader on Linux PC. Fedora users can install `SDL` and `SDL-devel` package.
Ubuntu users probably need to install `libsdl2-dev` package:

Getting the source
==================

```
git clone https://github.com/koreader/koreader.git
cd koreader && ./kodev fetch-thirdparty
```

Building, Running and Testing
=============================

For EReader devices (kindle, kobo, pocketbook, ubuntu-touch)
---------------------

To build installable package for Kindle:
```
./kodev release kindle
```

To build installable package for Kobo:
```
./kodev release kobo
```

To build installable package for PocketBook:
```
./kodev release pocketbook
```

To build installable package for Ubuntu Touch
```
./kodev release ubuntu-touch
```

You may checkout our [nightlybuild script][nb-script] to see how to build a
package from scratch.

For Android devices
-------------------

Make sure the "android" and "ndk-build" tools are in your PATH environment
variable and the NDK variable points to the root directory of the Android NDK.

Then, run this command to build installable package for Android:
```
./kodev release android
```

For emulating KOReader on Linux, Windows and Mac OSX
-------------

To build an emulator on current Linux or OSX machine:
```
./kodev build
```

If you want to compile the emulator for Windows run:
```
./kodev build win32
```

To run Koreader on your developing machine:
```
./kodev run
```

To run unit tests:
```
./kodev test base
./kodev test front
```

To run Lua static analysis:
```
make static-check
```

You may need to checkout the [travis config file][travis-conf] to setup up
a proper testing environment. Briefly, you need to install `luarocks` and
then install `busted` with `luarocks`. The "eng" language data file for
tesseract-ocr is also need to test OCR functionality. Finally, make sure
that `luajit` in your system is at least of version 2.0.2.

You can also specify size of emulator's screen via environment variables.
For more information, please refer to [koreader-base's README][base-readme].

To use your own koreader-base repo instead of the default one change KOR_BASE
environment variable:
```
make KOR_BASE=../koreader-base
```

This will be handy if you are developing koreader-base and want to test your
modifications with kroeader frontend. NOTE: only support relative path for now.


Translation
===========

Please refer to [l10n's README][l10n-readme] to grab the latest translations
from [the Koreader project on Transifex][koreader-transifex] with this command:
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
when the same compilation is being done again. In other words, it will decrease
build time when the source have been built. Ccache support has been added to
KOReader's build system. Before using it, you need to install a ccache in your
system.

* in Ubuntu use:`sudo apt-get install ccache`
* in Fedora use:`sudo yum install ccache`
* install from source:
  * get latest ccache source from http://ccache.samba.org/download.html
  * unarchieve the source package in a directory
  * cd to that directory and use:`./configure && make && sudo make install`
* to disable ccache, use `export USE_NO_CCACHE=1` before make.
* for more detail about ccache. visit:

http://ccache.samba.org


[base-readme]:https://github.com/koreader/koreader-base/blob/master/README.md
[nb-script]:https://github.com/koreader/koreader-misc/blob/master/koreader-nightlybuild/koreader-nightlybuild.sh
[travis-badge]:https://travis-ci.org/koreader/koreader.svg?branch=master
[travis-link]:https://travis-ci.org/koreader/koreader
[travis-conf]:https://github.com/koreader/koreader-base/blob/master/.travis.yml
[linux-vm]:http://www.howtogeek.com/howto/11287/how-to-run-ubuntu-in-windows-7-with-vmware-player/
[l10n-readme]:https://github.com/koreader/koreader/blob/master/l10n/README.md
[koreader-transifex]:https://www.transifex.com/projects/p/koreader/
[coverage-badge]:https://coveralls.io/repos/koreader/koreader/badge.svg
[coverage-link]:https://coveralls.io/r/koreader/koreader
[licence-badge]:http://img.shields.io/badge/licence-AGPL-brightgreen.svg
[gitter-badge]:https://badges.gitter.im/Join%20Chat.svg
[gitter-link]:https://gitter.im/koreader/koreader?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge
