Koreader
========

This is a document viewer application, created for usage on the Kindle e-ink reader.
It currently supports Kindle 5 (Touch) and Kindle Paperwhite. The devices need
to be jailbroken in order to install the application. Also, a kind of external
launcher is needed.

Koreader started as the KindlePDFViewer application, but it supports much more
formats than PDF now. Among them are DJVU, FB2, EPUB, TXT, CBZ, HTML.

Koreader is a frontend written in Lua and uses the API presented by the
Koreader-base framework. Koreader implements a GUI and is currently targeted
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

	* automatically fetch thirdparty sources with Makefile:
		* make sure you have patch, wget, unzip, git and svn installed
		* run `make fetchthirdparty`.

* adapt Makefile to your needs - have a look at Makefile.defs in koreader-base

* run `make thirdparty`. This will build MuPDF (plus the libraries it depends
  on), libDjvuLibre, CREngine and Lua.

* run `make`. This will build the kpdfview application


Running
=======

The user interface is scripted in Lua. See "reader.lua".
It uses the Linux feature to run scripts by using a corresponding line at its
start.

So you might just call that script. Note that the script and the koreader-base
binary currently must be in the same directory.

You would then just call reader.lua, giving the document file path, or any
directory path, as its first argument. Run reader.lua without arguments to see
usage notes.  The reader.lua script can also show a file chooser: it will do
this when you call it with a directory (instead of a file) as first argument.


