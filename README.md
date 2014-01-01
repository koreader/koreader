KOReader
========

This is a document viewer application, originally created for usage on the
Kindle e-ink reader. It currently supports Kindle 5 (Touch), Kindle Paperwhite
and Kobo devices. Kindles need to be jailbroken in order to install the
application. Also, a kind of external launcher is needed.

KOReader started as the KindlePDFViewer application, but it supports much more
formats than PDF now. Among them are DJVU, FB2, EPUB, TXT, CBZ, HTML.

KOReader is a frontend written in Lua and uses the API presented by the
KOReader-base framework. KOReader implements a GUI and is currently targeted
at Touch-based devices - for the classic user interface for button-driven
e-ink devices (like the Kindle 2, Kindle DX, Kindle 3, Kindle 4) see the
KindlePDFviewer legacy project or - especially for the Kindle 4 - have a look
at its fork Librerator.

The application is licensed under the GPLv3 (see COPYING file).


Prerequisites
========

Instructions about how to get and compile the source are intended for a \*nix
OS. Windows users are suggested to develop in a Linux VM or use
andLinux, Wubi.

To get and compile the source you must have `patch`, `wget`, `unzip`, `git`,
`svn`, `autoconf` and `cmake` installed.

Version of autoconf need to be greater than 2.64.

You might also need SDL library packages if you want to compile and run the PC
emulator. Fedora users can install `SDL` and `SDL-devel`. Ubuntu users can
install `libsdl1.2-dev`.


Getting the source
========

```
git clone https://github.com/koreader/koreader.git
cd koreader
make fetchthirdparty
```


Building & Running
========

For real eink devices
---------------------

If you already done an emulator build, you must do:
```
make clean
```

To build for the Kindle:
```
make customupdate
```

To build for the Kobo:
```
make TARGET_DEVICE=KOBO koboupdate
```

To run, you must call the script reader.lua. Run it without arguments to see
usage notes. Note that the script and the koreader-base binary currently must
be in the same directory.

You may checkout our [nightlybuild script][nb-script] to see how to build a
package from scratch.

For emulating
-----------

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
