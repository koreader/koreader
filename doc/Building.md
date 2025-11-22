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
- `cmake`: version 3.17.5 or greater
- `gcc/g++` or `clang/clang++`: with C11 & C++17 support
- `git`
- `make`: version 4.1 or greater
- `meson`: version 1.2.0 or greater
- `nasm`
- `ninja`
- `patch`
- `perl`: version 5 or greater
- `pkg-config` or `pkgconf`
- `unzip`
- `wget`
- `python`

For running the emulator / tests:
- `SDL2`

Optional:
- `7z`: for packing releases
- `ccache`: recommended for faster recompilation times
- `gettext`: for updating translations
- `luacheck`: for linting the codebase with `./kodev check`

### Alpine Linux

Install the prerequisites using apk:

```
sudo apk add autoconf automake bash cmake coreutils curl diffutils \
    findutils g++ gcc git grep gzip libtool linux-headers make meson \
    nasm ninja-build patch perl pkgconf procps-ng sdl2 tar unzip wget
```

**Note:** don't forget to add `/usr/lib/ninja-build/bin` to `$PATH`
so the real ninja is used (and not the binary provided by samurai).

Optional:
```
sudo apk add 7zip ccache gettext-dev luacheck
```

### Arch Linux

Install the prerequisites using pacman:

```
run0 pacman -S base-devel ca-certificates cmake gcc-libs git \
    meson nasm ninja perl sdl2 unzip wget
```

Optional:
```
run0 pacman -S 7zip ccache luacheck
```

### Debian/Ubuntu

Install the prerequisites using APT:

```
sudo apt install autoconf automake build-essential ca-certificates cmake \
    gcc-multilib git libsdl2-2.0-0 libtool libtool-bin meson nasm ninja-build \
    patch perl pkg-config unzip wget
```

**Note:** Debian distributions might need `meson` to be installed from `bookworm-backports`) because the version provided by the default repositories is too old:
```
sudo apt install meson/bookworm-backports
```
The bookworm-backports repository was already included on Linux Mint Dedian Edition 6.
Otherwise, follow full up-to-date instructions from here: https://wiki.debian.org/Backports.

Optional:
```
sudo apt install ccache gettext lua-check p7zip-full
```

### Fedora/Red Hat

Install the prerequisites using DNF:

```
sudo dnf install autoconf automake cmake gcc gcc-c++ git libtool meson nasm \
    ninja-build patch perl-FindBin procps-ng SDL2 unzip wget
```

Optional:
```
sudo dnf install ccache gettext p7zip
```
And for luacheck:
```
sudo dnf install lua-argparse lua-filesystem luarocks
luarocks install luacheck
```

### macOS

Install the prerequisites using [Homebrew](https://brew.sh/):

```
brew install autoconf automake bash binutils cmake coreutils findutils \
    gnu-getopt libtool make meson nasm ninja pkg-config sdl2 util-linux
```

You will also have to ensure Homebrew's findutils, gnu-getopt, make & util-linux are in your path, e.g., via
```
export PATH="$(brew --prefix)/opt/findutils/libexec/gnubin:$(brew --prefix)/opt/gnu-getopt/bin:$(brew --prefix)/opt/make/libexec/gnubin:$(brew --prefix)/opt/util-linux/bin:${PATH}"
```

Optional:
```
brew install ccache gettext luacheck p7zip
```

*Note:* You can override the default targeted minimum deployment version by setting `MACOSX_DEPLOYMENT_TARGET`:
```
export MACOSX_DEPLOYMENT_TARGET=10.09
```

### Nix

Ensure the [nix is installed](https://nixos.org/download/).

Then simply run the included nix shell:
```
nix-shell tools/shell.nix
```

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
