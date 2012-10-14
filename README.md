KindlePDFViewer
===============

This is a document viewer application, created for usage on the Kindle e-ink reader.
It is currently restricted to 4bpp inverse grayscale displays. For PDF files
it is using the muPDF library (see http://mupdf.com/), for DjVu files djvulibre library
and for ebooks (fb2, mobi, ePub, etc) crengine. It can also read JPEG images using
libjpeg library. The user interface is scripted using Lua (see http://www.lua.org/).

The application is licensed under the GPLv3 (see COPYING file).


Building
========


Follow these steps:

* fetch thirdparty sources
	* manually fetch all the thirdparty sources:
		* install muPDF sources into subfolder "mupdf"
		* install muPDF third-party sources (see muPDF homepage) into a new
		subfolder "mupdf/thirdparty"
		* install libDjvuLibre sources into subfolder "djvulibre"
		* install CREngine sources into subfolder "kpvcrlib/crengine"
		* install LuaJit sources into subfolder "luajit-2.0"
		* install popen_noshell sources into subfolder "popen-noshell"

	* automatically fetch thirdparty sources with Makefile:
		* make sure you have patch, wget, unzip, git and svn installed
		* run `make fetchthirdparty`.

* adapt Makefile to your needs

* run `make thirdparty`. This will build MuPDF (plus the libraries it depends
  on), libDjvuLibre, CREngine and Lua.

* run `make`. This will build the kpdfview application


Running
=======

The user interface (or what's there yet) is scripted in Lua. See "reader.lua".
It uses the Linux feature to run scripts by using a corresponding line at its
start.

So you might just call that script. Note that the script and the kpdfview
binary currently must be in the same directory.

You would then just call reader.lua, giving the document file path, or any
directory path, as its first argument. Run reader.lua without arguments to see
usage notes.  The reader.lua script can also show a file chooser: it will do
this when you call it with a directory (instead of a file) as first argument.


Device emulation
================

The code also features a device emulation. You need SDL headers and library
for this. It allows to develop on a standard PC and saves precious development
time. It might also compose the most unfriendly desktop PDF reader, depending
on your view.

If you are using Ubuntu, simply install `libsdl-dev1.2` package.

To build in "emulation mode", you need to run make like this:
	make clean cleanthirdparty
	EMULATE_READER=1 make thirdparty kpdfview

And run the emulator like this:
```
./reader.lua /PATH/TO/PDF.pdf
```

or:
```
./reader.lua /ANY/PATH
```

By default emulation will provide DXG resolution of 824*1200. It can be
specified at compile time, this is example for Kindle 3:

```
EMULATE_READER_W=600 EMULATE_READER_H=800 EMULATE_READER=1 make kpdfview
```

