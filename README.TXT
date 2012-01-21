KindlePDFViewer
===============

This is a PDF viewer application, created for usage on the Kindle e-ink reader.
It is currently restricted to 4bpp inverse grayscale displays. It's using the
muPDF library (see http://mupdf.com/) and its UI is scripted using Lua (see
http://www.lua.org/).

The application is licensed under the GPLv3 (see COPYING file).


Building
========

Follow these steps:

- install muPDF sources into subfolder "mupdf"
- install muPDF third-party sources (see muPDF homepage) into a new subfolder
  "mupdf/thirdparty"

- install Lua sources into subfolder "lua"

=> note that there's a make target to do this. You need wget, unzip and git
   installed. Then just run "make fetchthirdparty".

- adapt Makefile to your needs

- run "make thirdparty". This will build MuPDF (plus the libraries it depends
  on) and Lua.

- run "make". This will build the kpdfview application


Running
=======

The user interface (or what's there yet) is scripted in Lua. See "reader.lua".
It uses the Linux feature to run scripts by using a corresponding line at its
start.
So you might just call that script. Note that the script and the kpdfview
binary currently must be in the same directory.
You would then just call reader.lua, giving the document file path as its first
argument. Run reader.lua without arguments to see usage notes.
The reader.lua script can also show a file chooser: it will do this when you
call it with a directory (instead of a file) as first argument.


Device emulation
================

The code also features a device emulation. You need SDL headers and library
for this. It allows to develop on a standard PC and saves precious development
time. It might also compose the most unfriendly desktop PDF reader, depending
on your view.

To build in "emulation mode", you need to run make like this:
	make clean cleanthirdparty
	EMULATE_READER=1 make thirdparty kpdfview

The reader.lua script needs a device argument in order to cope with some
slight differences between actual readers and the emulation. Run it like
this:
	./reader.lua -d emu /PATH/TO/PDF.pdf

By default emulation will provide DXG resolution of 824*1200. It can be
specified at compile time, this is example for Kindle 3:

	EMULATE_READER_W=600 EMULATE_READER_H=800 EMULATE_READER=1 make kpdfview

