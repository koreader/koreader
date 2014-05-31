KOReader [![Build Status][travis-icon]][travis-link]
========

KOReader is a document viewer application, originally created for usage on the
Kindle e-ink reader. It currently supports Kindle 5 (Touch), Kindle Paperwhite
, Kobo and Android devices.

KOReader started as the KindlePDFViewer application, but it supports much more
formats than PDF now. Among them are DJVU, FB2, EPUB, TXT, CBZ, HTML.

KOReader is a frontend written in Lua and uses the API presented by the
koreader-base framework. KOReader implements a GUI and is currently targeted
at touch-based devices - for the classic user interface for button-driven
e-ink devices (like the Kindle 2, Kindle DX, Kindle 3, Kindle 4) see the
KindlePDFviewer legacy project or - especially for the Kindle 4 - have a look
at its fork Librerator.

This application is distributed under the GNU AGPL v3 license (read the [COPYING](COPYING) file).

Check out the [KOReader wiki](https://github.com/koreader/koreader/wiki) to learn 
more about this project.

Prerequisites
========

Instructions about how to get and compile the source are intended for a linux
OS. Windows users are suggested to develop in a [Linux VM][linux-vm] or use Wubi.

To get and compile the source you must have `patch`, `wget`, `unzip`, `git`, `autoconf`, 
`subversion` and `cmake` installed. Version of autoconf need to be greater than 2.64.

Ubuntu users may need to run:
```
sudo apt-get install build-essential libtool
```

Cross compile toolchains are available for Ubuntu users through these commands:
```
# for Kindle
sudo apt-get install gcc-arm-linux-gnueabi g++-arm-linux-gnueabi
# for Kobo
sudo apt-get install gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
```

A recent version of Android SDK/NDK is needed in order to build Koreader for Android
devices.

You might also need SDL library packages if you want to compile and run 
Koreader on PC. Fedora users can install `SDL` and `SDL-devel`.
Ubuntu users probably need to run:
```
sudo apt-get install libsdl1.2-dev
```

Getting the source
========

```
git clone https://github.com/koreader/koreader.git
cd koreader
make fetchthirdparty
```


Building & Running & Testing
========

For real eink devices
---------------------

If you have already built one package for a different target, remember to run
this command before you go further:
```
make clean
```

To build installable package for Kindle:
```
make TARGET=kindle kindleupdate
```

To build installable package for Kobo:
```
make TARGET=kobo koboupdate
```

To run, you must call the script reader.lua. Run it without arguments to see
usage notes. Note that the script and the koreader-base binary currently must
be in the same directory.

You may checkout our [nightlybuild script][nb-script] to see how to build a
package from scratch.

For Android devices
-------------------

Make sure the "android" tool is in your PATH variable and the NDK variable
points to the root directory of the Android NDK.

First, run this command to make a standalone android cross compiling toolchain
from NDK:
```
make android-toolchain
```

Also, if you have already built a different target, remember to clear the source
code tree with:
```
make clean
```

Then, build installable package for Android:
```
make TARGET=android androidupdate
```

For emulating
-------------

If you already done a real device build, you must do:
```
make clean
```

To build:
```
EMULATE_READER=1 make
```

To run:
```
cd koreader-*/koreader && ./reader.lua -d ./
```

To test:
```
make test
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
EMULATE_READER=1 make KOR_BASE=../koreader-base
```

This will be handy if you are developing koreader-base and want to test your
modifications with kroeader frontend. NOTE: only support relative path for now.


Use ccache
==========

Ccache can speed up recompilation by caching previous compilations and detecting
when the same compilation is being done again. In other words, it will decrease
build time when the source have been built. Ccache support has been added to
KOReader's build system. Before using it, you need to install a ccache in your
system.

* in ubuntu use:`sudo apt-get install ccache`
* in fedora use:`sudo yum install ccache`
* install from source:
  * get latest ccache source from http://ccache.samba.org/download.html
  * unarchieve the source package in a directory
  * cd to that directory and use:`./configure && make && sudo make install`
* after using ccache, make a clean build will only take 15sec. Enjoy!
* to disable ccache, use `export USE_NO_CCACHE=1` before make.
* for more detail about ccache. visit:

http://ccache.samba.org


[base-readme]:https://github.com/koreader/koreader-base/blob/master/README.md
[nb-script]:https://github.com/koreader/koreader-misc/blob/master/koreader-nightlybuild/koreader-nightlybuild.sh
[travis-icon]:https://travis-ci.org/koreader/koreader-base.png?branch=master
[travis-link]:https://travis-ci.org/koreader/koreader-base
[travis-conf]:https://github.com/koreader/koreader-base/blob/master/.travis.yml
[linux-vm]:http://www.howtogeek.com/howto/11287/how-to-run-ubuntu-in-windows-7-with-vmware-player/

