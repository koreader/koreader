# you can probably leave these settings alone:

LUADIR=lua
MUPDFDIR=mupdf
MUPDFTARGET=build/debug
MUPDFLIBDIR=$(MUPDFDIR)/$(MUPDFTARGET)
DJVUDIR=djvulibre
KPVCRLIGDIR=kpvcrlib
CRENGINEDIR=$(KPVCRLIGDIR)/crengine

FREETYPEDIR=$(MUPDFDIR)/thirdparty/freetype-2.4.8
LFSDIR=luafilesystem

# must point to directory with *.ttf fonts for crengine
TTF_FONTS_DIR=/usr/share/fonts/truetype/freefont/

# set this to your ARM cross compiler:

CC:=arm-unknown-linux-gnueabi-gcc
CXX:=arm-unknown-linux-gnueabi-g++
HOST:=arm-unknown-linux-gnueabi
ifdef SBOX_UNAME_MACHINE
	CC:=gcc
	CXX:=g++
endif
HOSTCC:=gcc
HOSTCXX:=g++

CFLAGS:=-O3
ARM_CFLAGS:=-march=armv6
# use this for debugging:
#CFLAGS:=-O0 -g

# you can configure an emulation for the (eink) framebuffer here.
# the application won't use the framebuffer (and the special e-ink ioctls)
# in that case.

ifdef EMULATE_READER
	CC:=$(HOSTCC) -g
	CXX:=$(HOSTCXX)
	EMULATE_READER_W?=824
	EMULATE_READER_H?=1200
	EMU_CFLAGS?=$(shell sdl-config --cflags)
	EMU_CFLAGS+= -DEMULATE_READER \
		     -DEMULATE_READER_W=$(EMULATE_READER_W) \
		     -DEMULATE_READER_H=$(EMULATE_READER_H)
	EMU_LDFLAGS?=$(shell sdl-config --libs)
else
	CFLAGS+= $(ARM_CFLAGS)
endif

# standard includes
KPDFREADER_CFLAGS=$(CFLAGS) -I$(LUADIR)/src -I$(MUPDFDIR)/

# enable tracing output:

#KPDFREADER_CFLAGS+= -DMUPDF_TRACE

# for now, all dependencies except for the libc are compiled into the final binary:

MUPDFLIBS := $(MUPDFLIBDIR)/libfitz.a
DJVULIBS := $(DJVUDIR)/build/libdjvu/.libs/libdjvulibre.a
CRENGINELIBS := $(CRENGINEDIR)/crengine/libcrengine.a \
			$(CRENGINEDIR)/thirdparty/chmlib/libchmlib.a \
			$(CRENGINEDIR)/thirdparty/libpng/libpng.a \
			$(CRENGINEDIR)/thirdparty/antiword/libantiword.a
THIRDPARTYLIBS := $(MUPDFLIBDIR)/libfreetype.a \
			$(MUPDFLIBDIR)/libopenjpeg.a \
			$(MUPDFLIBDIR)/libjbig2dec.a \
			$(MUPDFLIBDIR)/libjpeg.a \
			$(MUPDFLIBDIR)/libz.a

#@TODO patch crengine to use the latest libjpeg  04.04 2012 (houqp)
			#$(MUPDFLIBDIR)/libjpeg.a 
			#$(CRENGINEDIR)/thirdparty/libjpeg/libjpeg.a

LUALIB := $(LUADIR)/src/liblua.a

all:kpdfview slider_watcher

kpdfview: kpdfview.o einkfb.o pdf.o blitbuffer.o drawcontext.o input.o util.o ft.o lfs.o $(MUPDFLIBS) $(THIRDPARTYLIBS) $(LUALIB) djvu.o $(DJVULIBS) cre.o $(CRENGINELIBS)
	$(CC) -lm -ldl -lpthread $(EMU_LDFLAGS) -lstdc++ \
		kpdfview.o \
		einkfb.o \
		pdf.o \
		blitbuffer.o \
		drawcontext.o \
		input.o \
		util.o \
		ft.o \
		lfs.o \
		$(MUPDFLIBS) \
		$(THIRDPARTYLIBS) \
		$(LUALIB) \
		djvu.o \
		$(DJVULIBS) \
		cre.o \
		$(CRENGINELIBS) \
		-o kpdfview

einkfb.o input.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) $(EMU_CFLAGS) $< -o $@

slider_watcher: slider_watcher.c
	$(CC) $(CFLAGS) $< -o $@

ft.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(FREETYPEDIR)/include $< -o $@

kpdfview.o pdf.o blitbuffer.o util.o drawcontext.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(LFSDIR)/src $< -o $@

djvu.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(DJVUDIR)/ $< -o $@

cre.o: %.o: %.cpp
	$(CC) -c -I$(CRENGINEDIR)/crengine/include/ -Ilua/src $< -o $@ -lstdc++

lfs.o: $(LFSDIR)/src/lfs.c
	$(CC) -c $(CFLAGS) -I$(LUADIR)/src -I$(LFSDIR)/src $(LFSDIR)/src/lfs.c -o $@

fetchthirdparty:
	-rm -Rf lua lua-5.1.4
	-rm -Rf mupdf/thirdparty
	git submodule init
	git submodule update
	ln -sf kpvcrlib/crengine/cr3gui/data data
	test -d fonts || ln -sf $(TTF_FONTS_DIR) fonts
	test -f mupdf-thirdparty.zip || wget http://www.mupdf.com/download/mupdf-thirdparty.zip
	unzip mupdf-thirdparty.zip -d mupdf
	cd mupdf/thirdparty/jpeg-*/ && \
		patch -N -p0 < ../../../kpvcrlib/jpeg_compress_struct_size.patch &&\
		patch -N -p0 < ../../../kpvcrlib/jpeg_decompress_struct_size.patch
	test -f lua-5.1.4.tar.gz || wget http://www.lua.org/ftp/lua-5.1.4.tar.gz
	tar xvzf lua-5.1.4.tar.gz && ln -s lua-5.1.4 lua

clean:
	-rm -f *.o kpdfview slider_watcher

cleanthirdparty:
	make -C $(LUADIR) clean
	make -C $(MUPDFDIR) clean
	make -C $(CRENGINEDIR)/thirdparty/antiword clean
	make -C $(CRENGINEDIR)/thirdparty/chmlib clean
	make -C $(CRENGINEDIR)/thirdparty/libpng clean
	make -C $(CRENGINEDIR)/crengine clean
	make -C $(KPVCRLIGDIR) clean
	-rm -rf $(DJVUDIR)/build
	-rm -f $(MUPDFDIR)/fontdump.host
	-rm -f $(MUPDFDIR)/cmapdump.host

$(MUPDFDIR)/fontdump.host:
	make -C mupdf CC="$(HOSTCC)" $(MUPDFTARGET)/fontdump
	cp -a $(MUPDFLIBDIR)/fontdump $(MUPDFDIR)/fontdump.host
	make -C mupdf clean

$(MUPDFDIR)/cmapdump.host:
	make -C mupdf CC="$(HOSTCC)" $(MUPDFTARGET)/cmapdump
	cp -a $(MUPDFLIBDIR)/cmapdump $(MUPDFDIR)/cmapdump.host
	make -C mupdf clean

$(MUPDFLIBS) $(THIRDPARTYLIBS): $(MUPDFDIR)/cmapdump.host $(MUPDFDIR)/fontdump.host
	# build only thirdparty libs, libfitz and pdf utils, which will care for libmupdf.a being built
	CFLAGS="$(CFLAGS)" make -C mupdf CC="$(CC)" CMAPDUMP=cmapdump.host FONTDUMP=fontdump.host MUPDF= XPS_APPS=

$(DJVULIBS):
	-mkdir $(DJVUDIR)/build
ifdef EMULATE_READER
	cd $(DJVUDIR)/build && ../configure --disable-desktopfiles --disable-shared --enable-static
else
	cd $(DJVUDIR)/build && ../configure --disable-desktopfiles --disable-shared --enable-static --host=$(HOST) --disable-xmltools --disable-desktopfiles
endif
	make -C $(DJVUDIR)/build

$(CRENGINELIBS):
	cd $(KPVCRLIGDIR) && rm -rf CMakeCache.txt CMakeFiles && \
		CFLAGS="$(CFLAGS)" CC="$(CC)" CXX="$(CXX)" cmake . && \
		make

$(LUALIB):
	make -C lua/src CC="$(CC)" CFLAGS="$(CFLAGS)" MYCFLAGS=-DLUA_USE_LINUX MYLIBS="-Wl,-E" liblua.a

thirdparty: $(MUPDFLIBS) $(THIRDPARTYLIBS) $(LUALIB) $(DJVULIBS) $(CRENGINELIBS)

INSTALL_DIR=kindlepdfviewer

install:
	# install to kindle using USB networking
	scp kpdfview *.lua root@192.168.2.2:/mnt/us/$(INSTALL_DIR)/
	scp launchpad/* root@192.168.2.2:/mnt/us/launchpad/

VERSION?=$(shell git rev-parse --short HEAD)
customupdate: kpdfview
	# ensure that build binary is for ARM
	file kpdfview | grep ARM || exit 1
	mkdir $(INSTALL_DIR)
	cp -p README.TXT COPYING kpdfview slider_watcher *.lua $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/data
	cp -rpL data/*.css $(INSTALL_DIR)/data
	cp -rp fonts $(INSTALL_DIR)
	zip -r kindlepdfviewer-$(VERSION).zip $(INSTALL_DIR) launchpad/
	rm -Rf $(INSTALL_DIR)
	@echo "copy kindlepdfviewer-$(VERSION).zip to /mnt/us/customupdates and install with shift+shift+I"
