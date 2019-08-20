# Setting up a build environment for KOReader

These instructions are intended to build the emulator in Linux and MacOS. Windows users are suggested to develop in a [Linux VM](https://www.howtogeek.com/howto/11287/how-to-run-ubuntu-in-windows-7-with-vmware-player/) or using the [Windows Subsystem for Linux](https://en.wikipedia.org/wiki/Windows_Subsystem_for_Linux).

If you only want to work with Lua frontend stuff, you can grab the AppImage and
run it with `--appimage-extract`.

You can skip most of the following instructions if desired, and use our premade Docker image instead. In that case the only requirements are Git and Docker. See [the virtual development environment README](https://github.com/koreader/virdevenv) for more information.

## Prerequisites

To get and compile the source you must have `patch`, `wget`, `unzip`, `git`,
`cmake` and `luarocks` installed, as well as a version of `autoconf`
greater than 2.64. You also need `nasm` and of course a compiler like `gcc`
or `clang`.

### Debian/Ubuntu and derivates

Install the prerequisites using APT:

```
sudo apt-get install build-essential git patch wget unzip \
gettext autoconf automake cmake libtool nasm luarocks libsdl2-dev \
libssl-dev libffi-dev libsdl2-dev libc6-dev-i386 xutils-dev linux-libc-dev:i386 zlib1g:i386
```


### Fedora/Red Hat

Install the `libstdc++-static`, `SDL` and `SDL-devel` packages using DNF:

```
sudo dnf install libstdc++-static SDL SDL-devel
```

### MacOS

Install the prerequisites using [Homebrew](https://brew.sh/):

```
brew install nasm binutils libtool autoconf automake cmake makedepend \
sdl2 lua@5.1 luarocks gettext pkg-config wget md5sha1sum
echo 'export PATH="/usr/local/opt/gettext/bin:$PATH"' >> "$HOME"/.bash_profile
```

If you run into a gettext error while building glib, try `brew link --force gettext` to override the built-in Mac OS BSD gettext with GNU GetText.

*Note:* in Mojave (10.14) you need to set a minimum deployment version higher than 10.04. Otherwise you'll get the error `ld: library not found for -lgcc_s.10.4`.
```
export MACOSX_DEPLOYMENT_TARGET=10.09
```


## Getting the source


```
git clone https://github.com/koreader/koreader.git
cd koreader && ./kodev fetch-thirdparty
```

Building the emulator

## Building and running the emulator

To build an emulator on your Linux or MacOS machine:

```
./kodev build
```

To run KOReader on your development machine:

```
./kodev run
```


You can specify the size and DPI of the emulator's screen using
`-w=X` (width), `-h=X` (height), and `-d=X` (DPI).

 There is also a convenience
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

## Building for other platforms

Once you have the emulator ready to rock you can [build for other platforms too](Building_targets.md).

## Testing

You may need to check out the [circleci config file][circleci-conf] to setup up
a proper testing environment. 

Briefly, you need to install `luarocks` and then install `busted` and `ansicolors` with `luarocks`. The "eng" language data file for tesseract-ocr is also need to test OCR functionality. Finally, make sure that `luajit` in your system is at least of version 2.0.2.

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

To run Lua static analysis:

```
make static-check
```

NOTE: Extra dependencies for tests: `luacheck` from luarocks.

## Translations

Please refer to [l10n's README][l10n-readme] to grab the latest translations
from [the KOReader project on Transifex][koreader-transifex] with this command:

```
make po
```

If your language is not listed on the Transifex project, please don't hesitate
to send a language request [here][koreader-transifex].

### Variables in translation

Some strings contain variables that should remain unaltered in translation. These take the form of a `%` followed by a number from `1-99`, although you'll seldom see more than about 5 in practice. Please don't put any spaces between the `%` and its number. `%1` should always remain `%1`.
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

## Use ccache

Ccache can speed up recompilation by caching previous compilations and detecting
when the same compilation is being repeated. In other words, it will decrease
build time when the sources have been built before. Ccache support has been added to
KOReader's build system. To install ccache:

* in Ubuntu use:`sudo apt-get install ccache`
* in Fedora use:`sudo dnf install ccache`
* from source:
  * download the latest ccache source from http://ccache.samba.org/download.html
  * extract the source package in a directory
  * `cd` to that directory and use:`./configure && make && sudo make install`
* to disable ccache, use `export USE_NO_CCACHE=1` before make.
* for more information about ccache, visit: https://ccache.samba.org/

[circleci-conf]:https://github.com/koreader/koreader/blob/master/.circleci/config.yml
[koreader-transifex]:https://www.transifex.com/projects/p/koreader/
[base-readme]:https://github.com/koreader/koreader-base/blob/master/README.md
[l10n-readme]:https://github.com/koreader/koreader/blob/master/l10n/README.md
