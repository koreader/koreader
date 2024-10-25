# Setting up a build environment for KOReader

These instructions are intended to build the emulator in Linux and macOS. Windows users are suggested to develop in a [Linux VM](https://www.howtogeek.com/howto/11287/how-to-run-ubuntu-in-windows-7-with-vmware-player/) or using the [Windows Subsystem for Linux](https://en.wikipedia.org/wiki/Windows_Subsystem_for_Linux).

If you only want to work with Lua frontend stuff, you can grab the AppImage and
run it with `--appimage-extract`.

You can skip most of the following instructions if desired, and use our premade Docker image instead. In that case the only requirements are Git and Docker. See [the virtual development environment README](https://github.com/koreader/virdevenv) for more information.

**Note:** If you want to use WSL then you'll need to export a sane PATH first, because Windows appends its own directories to it. You'll also need to [install an XServer](https://virtualizationreview.com/articles/2017/02/08/graphical-programs-on-windows-subsystem-on-linux.aspx). If you need more info please read <https://github.com/koreader/koreader/issues/6354>.

## Prerequisites

To get and compile the source you must have:
- `autoconf`: version greater than 2.64
- `bash`: version 4.0 or greater
- `ccache`: optional, but recommended
- `cmake`: version 3.15 or greater, 3.20 or greater recommended
- `gettext`
- `gcc/g++` or `clang/clang++`: with C11 & C++17 support
- `git`
- `make`: version 4.1 or greater
- `meson`: version 1.2.0 or greater
- `nasm`
- `ninja`: optional, but recommended
- `patch`
- `perl`: version 5 or greater
- `pkg-config` or `pkgconf`
- `unzip`
- `wget`

For testing:
- `busted`
- `lua`: version 5.1
- `luarocks`
- `SDL2`

### Alpine Linux

Install the prerequisites using apk:

```
sudo apk add autoconf automake bash cmake coreutils curl diffutils g++ \
    gcc gettext-dev git grep gzip libtool linux-headers lua5.1-busted \
    luarocks5.1 make meson ninja-build ninja-is-really-ninja patch \
    perl pkgconf procps-ng sdl2 tar unzip wget
```

### Arch Linux

Install the prerequisites using pacman:

```
run0 pacman -S base-devel ca-certificates cmake gcc-libs git \
    lua51-busted luarocks meson nasm ninja perl sdl2 unzip wget
```

### Debian/Ubuntu

Install the prerequisites using APT:

```
sudo apt-get install autoconf automake build-essential ca-certificates cmake \
    gcc-multilib gettext git libsdl2-2.0-0 libtool libtool-bin lua-busted \
    lua5.1 luarocks meson nasm ninja-build patch perl pkg-config unzip wget
```

**Note:** Debian distributions might need `meson` to be installed from `bookworm-backports`) because the version provided by the default repositories is too old:
```
sudo apt install meson/bookworm-backports
```
The bookworm-backports repository was already included on Linux Mint Dedian Edition 6.
Otherwise, follow full up-to-date instructions from here: https://wiki.debian.org/Backports.

### Fedora/Red Hat

Install the prerequisites using DNF:

```
sudo dnf install autoconf automake cmake gettext gcc gcc-c++ git libtool \
    lua5.1 luarocks meson nasm ninja-build patch perl-FindBin procps-ng \
    SDL2 unzip wget
```

And for busted:
```
luarocks --lua-version=5.1 --local install busted
```

### macOS

Install the prerequisites using [Homebrew](https://brew.sh/):

```
brew install autoconf automake binutils cmake coreutils findutils gnu-getopt \
    libtool make meson nasm ninja p7zip pkg-config sdl2 util-linux
```

You will also have to ensure Homebrew's findutils, gnu-getopt, make & util-linux are in your path, e.g., via
```
export PATH="$(brew --prefix)/opt/findutils/libexec/gnubin:$(brew --prefix)/opt/gnu-getopt/bin:$(brew --prefix)/opt/make/libexec/gnubin:$(brew --prefix)/opt/util-linux/bin:${PATH}"
```

In the same vein, if that's not already the case, you probably also want to make sure Homebrew's stuff takes precedence:
```
export PATH="/usr/local/bin:/usr/local/sbin:${PATH/:\/usr\/local\/bin/}"
```

*Note:* With current XCode versions, you *will* need to set a minimum deployment version higher than `10.04`. Otherwise, you'll hit various linking errors related to missing unwinding libraries/symbols.
On Mojave, `10.09` has been known to behave with XCode 10, And `10.14` with XCode 11. When in doubt, go with your current macOS version.
```
export MACOSX_DEPLOYMENT_TARGET=10.09
```
*Note:* On Catalina (10.15), you will currently *NOT* want to deploy for `10.15`, as [XCode is currently broken in that configuration](https://forums.developer.apple.com/thread/121887)! (i.e., deploy for `10.14` instead).

## Getting the source


```
git clone https://github.com/koreader/koreader.git
cd koreader && ./kodev fetch-thirdparty
```

Building the emulator

## Building and running the emulator

To build an emulator on your Linux or macOS machine:

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
from [the KOReader project on Weblate][koreader-weblate] with this command:

```
make po
```

If your language is not listed on the Weblate project, please don't hesitate
to send a language request [here][koreader-weblate].

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
build time when the sources have been built before. To install ccache use:

* Alpine Linux: `sudo apk add ccache`
* Arch Linux: `run0 pacman -S ccache`
* Debian/Ubuntu: `sudo apt-get install ccache`
* Fedora/Red Hat: `sudo dnf install ccache`
* macOS: `brew install ccache`
* or from an official release or source: https://github.com/ccache/ccache/releases

To disable ccache, use `export USE_NO_CCACHE=1` before make.

[circleci-conf]:https://github.com/koreader/koreader/blob/master/.circleci/config.yml
[koreader-weblate]:https://hosted.weblate.org/engage/koreader/
[base-readme]:https://github.com/koreader/koreader-base/blob/master/README.md
[l10n-readme]:https://github.com/koreader/koreader/blob/master/l10n/README.md
