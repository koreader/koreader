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
TTF_FONTS_DIR=$(MUPDFDIR)/fonts

# set this to your ARM cross compiler:

HOST:=arm-none-linux-gnueabi
CC:=$(HOST)-gcc
CXX:=$(HOST)-g++
STRIP:=$(HOST)-strip
ifdef SBOX_UNAME_MACHINE
	CC:=gcc
	CXX:=g++
endif
HOSTCC:=gcc
HOSTCXX:=g++

CFLAGS:=-O3 $(SYSROOT)
CXXFLAGS:=-O3 $(SYSROOT)
LDFLAGS:= $(SYSROOT)
ARM_CFLAGS:=-march=armv6
# use this for debugging:
#CFLAGS:=-O0 -g

DYNAMICLIBSTDCPP:=-lstdc++
ifdef STATICLIBSTDCPP
	DYNAMICLIBSTDCPP:=
endif

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
# we don't support dictionary lookup corrently
			#$(CRENGINEDIR)/thirdparty/antiword/libantiword.a
THIRDPARTYLIBS := $(MUPDFLIBDIR)/libfreetype.a \
			$(MUPDFLIBDIR)/libopenjpeg.a \
			$(MUPDFLIBDIR)/libjbig2dec.a \
			$(MUPDFLIBDIR)/libjpeg.a \
			$(MUPDFLIBDIR)/libz.a

#@TODO patch crengine to use the latest libjpeg  04.04 2012 (houqp)
			#$(MUPDFLIBDIR)/libjpeg.a \
			#$(CRENGINEDIR)/thirdparty/libjpeg/libjpeg.a \

LUALIB := $(LUADIR)/src/liblua.a

all:kpdfview

kpdfview: kpdfview.o einkfb.o pdf.o blitbuffer.o drawcontext.o input.o util.o ft.o lfs.o mupdfimg.o $(MUPDFLIBS) $(THIRDPARTYLIBS) $(LUALIB) djvu.o $(DJVULIBS) cre.o $(CRENGINELIBS)
	$(CC) -lm -ldl -lpthread $(EMU_LDFLAGS) $(DYNAMICLIBSTDCPP) \
		kpdfview.o \
		einkfb.o \
		pdf.o \
		blitbuffer.o \
		drawcontext.o \
		input.o \
		util.o \
		ft.o \
		lfs.o \
		mupdfimg.o \
		$(MUPDFLIBS) \
		$(THIRDPARTYLIBS) \
		$(LUALIB) \
		djvu.o \
		$(DJVULIBS) \
		cre.o \
		$(CRENGINELIBS) \
		$(STATICLIBSTDCPP) \
		-o kpdfview

slider_watcher: slider_watcher.c
	$(CC) $(CFLAGS) $< -o $@

ft.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(FREETYPEDIR)/include -I$(MUPDFDIR)/fitz $< -o $@

kpdfview.o pdf.o blitbuffer.o util.o drawcontext.o einkfb.o input.o mupdfimg.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) $(EMU_CFLAGS) -I$(LFSDIR)/src $< -o $@

djvu.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(DJVUDIR)/ $< -o $@

cre.o: %.o: %.cpp
	$(CC) -c -I$(CRENGINEDIR)/crengine/include/ -Ilua/src $< -o $@ -lstdc++

lfs.o: $(LFSDIR)/src/lfs.c
	$(CC) -c $(CFLAGS) -I$(LUADIR)/src -I$(LFSDIR)/src $(LFSDIR)/src/lfs.c -o $@

fetchthirdparty:
	-rm -Rf lua lua-5.1.4
	-rm -Rf mupdf/thirdparty
	test -d mupdf && (cd mupdf; git checkout .)  || echo warn: mupdf folder not found
	git submodule init
	git submodule update
	ln -sf kpvcrlib/crengine/cr3gui/data data
	test -d fonts || ln -sf $(TTF_FONTS_DIR) fonts
	# CREngine patch: disable fontconfig
	grep USE_FONTCONFIG $(CRENGINEDIR)/crengine/include/crsetup.h && grep -v USE_FONTCONFIG $(CRENGINEDIR)/crengine/include/crsetup.h > /tmp/new && mv /tmp/new $(CRENGINEDIR)/crengine/include/crsetup.h || echo "USE_FONTCONFIG already disabled"
	test -f mupdf-thirdparty.zip || wget http://www.mupdf.com/download/mupdf-thirdparty.zip
	# CREngine patch: change child nodes' type face
	# @TODO replace this dirty hack  24.04 2012 (houqp)
	cd kpvcrlib/crengine/crengine/src && \
		patch -N -p0 < ../../../lvrend_node_type_face.patch
	unzip mupdf-thirdparty.zip -d mupdf
	# dirty patch in MuPDF's thirdparty liby for CREngine
	cd mupdf/thirdparty/jpeg-*/ && \
		patch -N -p0 < ../../../kpvcrlib/jpeg_compress_struct_size.patch &&\
		patch -N -p0 < ../../../kpvcrlib/jpeg_decompress_struct_size.patch
	# MuPDF patch: use external fonts
	cd mupdf && patch -N -p1 < ../mupdf.patch
	test -f lua-5.1.4.tar.gz || wget http://www.lua.org/ftp/lua-5.1.4.tar.gz
	tar xvzf lua-5.1.4.tar.gz && ln -s lua-5.1.4 lua

clean:
	-rm -f *.o kpdfview slider_watcher

cleanthirdparty:
	make -C $(LUADIR) clean
	make -C $(MUPDFDIR) clean
	#make -C $(CRENGINEDIR)/thirdparty/antiword clean
	test -d $(CRENGINEDIR)/thirdparty/chmlib && make -C $(CRENGINEDIR)/thirdparty/chmlib clean || echo warn: chmlib folder not found
	test -d $(CRENGINEDIR)/thirdparty/libpng && (make -C $(CRENGINEDIR)/thirdparty/libpng clean) || echo warn: chmlib folder not found
	test -d $(CRENGINEDIR)/crengine && (make -C $(CRENGINEDIR)/crengine clean) || echo warn: chmlib folder not found
	test -d $(KPVCRLIGDIR) && (make -C $(KPVCRLIGDIR) clean) || echo warn: chmlib folder not found
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
	CFLAGS="$(CFLAGS) -DNOBUILTINFONT" make -C mupdf CC="$(CC)" CMAPDUMP=cmapdump.host FONTDUMP=fontdump.host MUPDF= MU_APPS= BUSY_APP= XPS_APPS= verbose=1

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
customupdate: all
	# ensure that build binary is for ARM
	file kpdfview | grep ARM || exit 1
	$(STRIP) --strip-unneeded kpdfview
	-rm kindlepdfviewer-$(VERSION).zip
	rm -Rf $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)
	cp -p README.TXT COPYING kpdfview *.lua $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/data
	cp -rpL data/*.css $(INSTALL_DIR)/data
	cp -rpL fonts $(INSTALL_DIR)
	cp -r resources $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/fonts/host
	zip -9 -r kindlepdfviewer-$(VERSION).zip $(INSTALL_DIR) launchpad/
	rm -Rf $(INSTALL_DIR)
	@echo "copy kindlepdfviewer-$(VERSION).zip to /mnt/us/customupdates and install with shift+shift+I"
