KOReader
========

This is a document viewer application, created for usage on the Kindle e-ink reader.
It currently supports Kindle 5 (Touch) and Kindle Paperwhite. The devices need
to be jailbroken in order to install the application. Also, a kind of external
launcher is needed.
>本文档阅读软件为kindle电子墨水阅读器用户使用而创建。目前该软件支持Kindle 5 (Touch)和Kindle Paperwhite。这些设备首先需要通过越狱然后才能安装KOReader，同时还需要一种额外的启动器。

KOReader started as the KindlePDFViewer application, but it supports much more
formats than PDF now. Among them are DJVU, FB2, EPUB, TXT, CBZ, HTML.

KOReader is a frontend written in Lua and uses the API presented by the
KOReader-base framework. KOReader implements a GUI and is currently targeted
at Touch-based devices - for the classic user interface for button-driven
e-ink devices (like the Kindle 2, Kindle DX, Kindle 3, Kindle 4) see the
KindlePDFviewer legacy project or - especially for the Kindle 4 - have a look
at its fork Librerator.

The application is licensed under the GPLv3 (see COPYING file).


Building
========


Follow these steps:

* fetch thirdparty sources
	* manually fetch all the thirdparty sources:
		* init and update submodule koreader-base
		* within koreader-base:
			* install muPDF sources into subfolder "mupdf"
			* install muPDF third-party sources (see muPDF homepage) into a new
			  subfolder "mupdf/thirdparty"
			* install libDjvuLibre sources into subfolder "djvulibre"
			* install CREngine sources into subfolder "kpvcrlib/crengine"
			* install LuaJit sources into subfolder "luajit-2.0"
			* install popen_noshell sources into subfolder "popen-noshell"
			* install libk2pdfopt sources into subfolder "libk2pdfopt"

	* automatically fetch thirdparty sources with Makefile:
		* make sure you have patch, wget, unzip, git and svn installed
		* run `make fetchthirdparty`.

* adapt Makefile to your needs - have a look at Makefile.defs in koreader-base

* run `make thirdparty`. This will build MuPDF (plus the libraries it depends
  on), libDjvuLibre, CREngine, libk2pdfopt and Lua.

* run `make`. This will build the KOReader application (see below if you want
  to build in emulation mode so you can test it on PC)


Running
=======

In real eink devices
---------------------
The user interface is scripted in Lua. See "reader.lua".
It uses the Linux feature to run scripts by using a corresponding line at its
start.

So you might just call that script. Note that the script and the koreader-base
binary currently must be in the same directory.

You would then just call reader.lua, giving the document file path, or any
directory path, as its first argument. Run reader.lua without arguments to see
usage notes.  The reader.lua script can also show a file chooser: it will do
this when you call it with a directory (instead of a file) as first argument.


In emulator
-----------
You need to first compile KOReader-base in emulation mode.
  * If you have built KOReader in real mode before, you need to clean it up:

```
make clean && make cleanthirdparty
```

  * Then compile with emulation mode flag:

```
EMULATE_READER=1 make
```

  * You may want to see README.md in koreader-base for more information.


Next run `make bootstrapemu` to setup basic runtime environment needed by
emulation mode. A new emu directory will be created.


Last, run the emulator with following command:
```
cd emu && reader.lua -d ./
```

You can also specify size of emulator's screen via environment variables.
For more information, please refer to [koreader-base's README][base-readme].

[base-readme]:https://github.com/koreader/koreader-base/blob/master/README.md
