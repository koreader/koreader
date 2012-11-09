# you can probably leave these settings alone:

LUADIR=luajit-2.0
MUPDFDIR=mupdf
MUPDFTARGET=build/release
MUPDFLIBDIR=$(MUPDFDIR)/$(MUPDFTARGET)
DJVUDIR=djvulibre
KPVCRLIBDIR=kpvcrlib
CRENGINEDIR=$(KPVCRLIBDIR)/crengine

FREETYPEDIR=$(MUPDFDIR)/thirdparty/freetype-2.4.10
JPEGDIR=$(MUPDFDIR)/thirdparty/jpeg-9
LFSDIR=luafilesystem

POPENNSDIR=popen-noshell
K2PDFOPTLIBDIR=libk2pdfopt

# must point to directory with *.ttf fonts for crengine
TTF_FONTS_DIR=$(MUPDFDIR)/fonts

# set this to your ARM cross compiler:

SHELL:=/bin/bash
CHOST?=arm-none-linux-gnueabi
CC:=$(CHOST)-gcc
CXX:=$(CHOST)-g++
STRIP:=$(CHOST)-strip
AR:=$(CHOST)-ar
ifdef SBOX_UNAME_MACHINE
	CC:=gcc
	CXX:=g++
endif
HOSTCC:=gcc
HOSTCXX:=g++
HOSTAR:=ar

# Base CFLAGS, without arch. We'll need it for luajit, because its Makefiles do some tricky stuff to differentiate HOST/TARGET
BASE_CFLAGS:=-O2 -ffast-math -pipe -fomit-frame-pointer
KOPT_CFLAGS:=-O3 -ffast-math -pipe -fomit-frame-pointer
# Use this for debugging:
#BASE_CFLAGS:=-O0 -g
# Misc GCC tricks to ensure backward compatibility with the K2, even when using a fairly recent TC (Linaro/MG).
# NOTE: -mno-unaligned-access is needed for TC based on Linaro 4.6/4.7 or GCC 4.7, or weird crap happens on FW 2.x. We unfortunately can't set it by default, since it's a new flag.
# A possible workaround would be to set the alignment trap to fixup (echo 2 > /proc/cpu/alignment) in the launch script, but that's terribly ugly, and might severly nerf performance...
# That said, MG 2012.03 is still using GCC 4.6.3, so we're good ;).
ARM_BACKWARD_COMPAT_CFLAGS:=-fno-stack-protector -U_FORTIFY_SOURCE -D_GNU_SOURCE -fno-finite-math-only
ARM_BACKWARD_COMPAT_CXXFLAGS:=-fno-use-cxa-atexit
ARM_ARCH:=-march=armv6j -mtune=arm1136jf-s -mfpu=vfp -mfloat-abi=softfp -marm
HOST_ARCH:=-march=native
HOSTCFLAGS:=$(HOST_ARCH) $(BASE_CFLAGS)
CFLAGS:=$(BASE_CFLAGS)
CXXFLAGS:=$(BASE_CFLAGS)
LDFLAGS:=-Wl,-O1 -Wl,--as-needed

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
	AR:=$(HOSTAR)
	EMULATE_READER_W?=824
	EMULATE_READER_H?=1200
	EMU_CFLAGS?=$(shell sdl-config --cflags)
	EMU_CFLAGS+= -DEMULATE_READER \
		     -DEMULATE_READER_W=$(EMULATE_READER_W) \
		     -DEMULATE_READER_H=$(EMULATE_READER_H)
	EMU_LDFLAGS?=$(shell sdl-config --libs)
	ifeq "$(shell uname -s -m)" "Darwin x86_64"
		EMU_LDFLAGS += -pagezero_size 10000 -image_base 100000000
	endif
	CFLAGS+= $(HOST_ARCH)
	CXXFLAGS+= $(HOST_ARCH)
	LIBDIR=libs-emu
else
	CFLAGS+= $(ARM_ARCH) $(ARM_BACKWARD_COMPAT_CFLAGS)
	CXXFLAGS+= $(ARM_ARCH) $(ARM_BACKWARD_COMPAT_CFLAGS) $(ARM_BACKWARD_COMPAT_CXXFLAGS)
	LIBDIR=libs
endif

# standard includes
KPDFREADER_CFLAGS=$(CFLAGS) -I$(LUADIR)/src -I$(MUPDFDIR)/
K2PDFOPT_CFLAGS=-I$(MUPDFDIR)/ -I$(DJVUDIR)/ -I$(K2PDFOPTLIBDIR)/

# enable tracing output:

#KPDFREADER_CFLAGS+= -DMUPDF_TRACE

# for now, all dependencies except for the libc are compiled into the final binary:

MUPDFLIBS := $(MUPDFLIBDIR)/libfitz.a
DJVULIBS := $(DJVUDIR)/build/libdjvu/.libs/libdjvulibre.so \
			$(LIBDIR)/libdjvulibre.so
DJVULIBDIR := $(DJVUDIR)/build/libdjvu/.libs/
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
			#$(MUPDFLIBDIR)/libjpeg.a \
			#$(CRENGINEDIR)/thirdparty/libjpeg/libjpeg.a \

LUALIB := $(LUADIR)/src/libluajit.a

POPENNSLIB := $(POPENNSDIR)/libpopen_noshell.a

K2PDFOPTLIB := $(LIBDIR)/libk2pdfopt.so

all: kpdfview extr

VERSION?=$(shell git describe HEAD)
kpdfview: kpdfview.o einkfb.o pdf.o blitbuffer.o drawcontext.o koptcontext.o input.o $(POPENNSLIB) util.o ft.o lfs.o mupdfimg.o $(MUPDFLIBS) $(THIRDPARTYLIBS) $(LUALIB) djvu.o $(DJVULIBS) cre.o $(CRENGINELIBS) pic.o pic_jpeg.o
	echo $(VERSION) > git-rev
	$(CC) \
		$(CFLAGS) \
		kpdfview.o \
		einkfb.o \
		pdf.o \
		blitbuffer.o \
		drawcontext.o \
		koptcontext.o \
		input.o \
		$(POPENNSLIB) \
		util.o \
		ft.o \
		lfs.o \
		mupdfimg.o \
		$(MUPDFLIBS) \
		$(THIRDPARTYLIBS) \
		$(LUALIB) \
		djvu.o \
		pic.o \
		pic_jpeg.o \
		cre.o \
		$(CRENGINELIBS) \
		$(STATICLIBSTDCPP) \
		$(LDFLAGS) \
		-o $@ \
		-lm -ldl -lpthread -lk2pdfopt -ldjvulibre -ljpeg -L$(MUPDFLIBDIR) -L$(LIBDIR)\
		$(EMU_LDFLAGS) \
		$(DYNAMICLIBSTDCPP)

extr:	extr.o $(MUPDFLIBS) $(THIRDPARTYLIBS)
	$(CC) $(CFLAGS) extr.o $(MUPDFLIBS) $(THIRDPARTYLIBS) -lm -o extr

extr.o:	%.o: %.c
	$(CC) -c -I$(MUPDFDIR)/pdf -I$(MUPDFDIR)/fitz $< -o $@

slider_watcher.o: %.o: %.c
	$(CC) -c $(CFLAGS) $< -o $@

slider_watcher: slider_watcher.o $(POPENNSLIB)
	$(CC) $(CFLAGS) slider_watcher.o $(POPENNSLIB) -o $@

ft.o: %.o: %.c $(THIRDPARTYLIBS)
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(FREETYPEDIR)/include -I$(MUPDFDIR)/fitz $< -o $@

blitbuffer.o util.o drawcontext.o einkfb.o input.o mupdfimg.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) $(EMU_CFLAGS) -I$(LFSDIR)/src $< -o $@

kpdfview.o koptcontext.o pdf.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) $(K2PDFOPT_CFLAGS) $(EMU_CFLAGS) -I$(LFSDIR)/src $< -o $@

djvu.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) $(K2PDFOPT_CFLAGS) -I$(DJVUDIR)/ $< -o $@

pic.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) $< -o $@

pic_jpeg.o: %.o: %.c
	$(CC) -c $(KPDFREADER_CFLAGS) -I$(JPEGDIR)/ -I$(MUPDFDIR)/scripts/ $< -o $@

cre.o: %.o: %.cpp
	$(CC) -c $(CFLAGS) -I$(CRENGINEDIR)/crengine/include/ -I$(LUADIR)/src $< -o $@

lfs.o: $(LFSDIR)/src/lfs.c
	$(CC) -c $(CFLAGS) -I$(LUADIR)/src -I$(LFSDIR)/src $(LFSDIR)/src/lfs.c -o $@

fetchthirdparty:
	rm -rf mupdf/thirdparty
	test -d mupdf && (cd mupdf; git checkout .)  || echo warn: mupdf folder not found
	test -d $(LUADIR) && (cd $(LUADIR); git checkout .)  || echo warn: $(LUADIR) folder not found
	git submodule init
	git submodule update
	ln -sf kpvcrlib/crengine/cr3gui/data data
	test -e data/cr3.css || ln kpvcrlib/cr3.css data/
	test -d fonts || ln -sf $(TTF_FONTS_DIR) fonts
	# CREngine patch: disable fontconfig
	grep USE_FONTCONFIG $(CRENGINEDIR)/crengine/include/crsetup.h && grep -v USE_FONTCONFIG $(CRENGINEDIR)/crengine/include/crsetup.h > /tmp/new && mv /tmp/new $(CRENGINEDIR)/crengine/include/crsetup.h || echo "USE_FONTCONFIG already disabled"
	test -f mupdf-thirdparty.zip || wget http://www.mupdf.com/download/mupdf-thirdparty.zip
	# CREngine patch: change child nodes' type face
	# @TODO replace this dirty hack  24.04 2012 (houqp)
	cd kpvcrlib/crengine/crengine/src && \
		patch -N -p0 < ../../../lvrend_node_type_face.patch && \
		patch -N -p3 < ../../../lvdocview-getCurrentPageLinks.patch || true
	unzip mupdf-thirdparty.zip -d mupdf
	# check mupdf's thirdparty libs' version, if not matched, remove the old one
	# run make fetchthirdparty again to get the latest thirdparty libs.
	test -d $(FREETYPEDIR) || ( echo "error: mupdf's thirdparty libs' version not match" ; \
		rm -rf mupdf-thirdparty.zip ; exit 1 )
	# dirty patch in MuPDF's thirdparty lib for CREngine
	cd mupdf/thirdparty/jpeg-*/ && \
		patch -N -p0 < ../../../kpvcrlib/jpeg_compress_struct_size.patch &&\
		patch -N -p0 < ../../../kpvcrlib/jpeg_decompress_struct_size.patch
	# MuPDF patch: use external fonts
	cd mupdf && patch -N -p1 < ../mupdf.patch
	test -f popen-noshell/popen_noshell.c || svn co http://popen-noshell.googlecode.com/svn/trunk/ popen-noshell
	# popen_noshell patch: Make it build on recent TCs, and implement a simple Makefile for building it as a static lib
	cd popen-noshell && test -f Makefile || patch -N -p0 < popen_noshell-buildfix.patch

clean:
	rm -f *.o kpdfview slider_watcher extr emu_event

cleanthirdparty:
	rm -rf $(LIBDIR) ; mkdir $(LIBDIR)
	$(MAKE) -C $(LUADIR) CC="$(HOSTCC)" CFLAGS="$(BASE_CFLAGS)" clean
	$(MAKE) -C $(MUPDFDIR) build="release" clean
	$(MAKE) -C $(CRENGINEDIR)/thirdparty/antiword clean
	test -d $(CRENGINEDIR)/thirdparty/chmlib && $(MAKE) -C $(CRENGINEDIR)/thirdparty/chmlib clean || echo warn: chmlib folder not found
	test -d $(CRENGINEDIR)/thirdparty/libpng && ($(MAKE) -C $(CRENGINEDIR)/thirdparty/libpng clean) || echo warn: chmlib folder not found
	test -d $(CRENGINEDIR)/crengine && ($(MAKE) -C $(CRENGINEDIR)/crengine clean) || echo warn: chmlib folder not found
	test -d $(KPVCRLIBDIR) && ($(MAKE) -C $(KPVCRLIBDIR) clean) || echo warn: chmlib folder not found
	rm -rf $(DJVUDIR)/build
	rm -f $(MUPDFDIR)/fontdump.host
	rm -f $(MUPDFDIR)/cmapdump.host
	$(MAKE) -C $(POPENNSDIR) clean
	$(MAKE) -C $(K2PDFOPTLIBDIR) clean

$(MUPDFDIR)/fontdump.host:
	CFLAGS="$(HOSTCFLAGS)" $(MAKE) -C mupdf build="release" CC="$(HOSTCC)" $(MUPDFTARGET)/fontdump
	cp -a $(MUPDFLIBDIR)/fontdump $(MUPDFDIR)/fontdump.host
	$(MAKE) -C mupdf clean

$(MUPDFDIR)/cmapdump.host:
	CFLAGS="$(HOSTCFLAGS)" $(MAKE) -C mupdf build="release" CC="$(HOSTCC)" $(MUPDFTARGET)/cmapdump
	cp -a $(MUPDFLIBDIR)/cmapdump $(MUPDFDIR)/cmapdump.host
	$(MAKE) -C mupdf clean

$(MUPDFLIBS) $(THIRDPARTYLIBS): $(MUPDFDIR)/cmapdump.host $(MUPDFDIR)/fontdump.host
	# build only thirdparty libs, libfitz and pdf utils, which will care for libmupdf.a being built
	CFLAGS="$(CFLAGS) -DNOBUILTINFONT" $(MAKE) -C mupdf build="release" CC="$(CC)" CMAPDUMP=cmapdump.host FONTDUMP=fontdump.host MUPDF= MU_APPS= BUSY_APP= XPS_APPS= verbose=1

$(DJVULIBS):
	mkdir -p $(DJVUDIR)/build
ifdef EMULATE_READER
	cd $(DJVUDIR)/build && CC="$(HOSTCC)" CXX="$(HOSTCXX)" CFLAGS="$(HOSTCFLAGS)" CXXFLAGS="$(HOSTCFLAGS)" LDFLAGS="$(LDFLAGS)" ../configure --disable-desktopfiles --disable-static --enable-shared --disable-xmltools --disable-largefile
else
	cd $(DJVUDIR)/build && CC="$(CC)" CXX="$(CXX)" CFLAGS="$(CFLAGS)" CXXFLAGS="$(CXXFLAGS)" LDFLAGS="$(LDFLAGS)" ../configure --disable-desktopfiles --disable-static --enable-shared --host=$(CHOST) --disable-xmltools --disable-largefile
endif
	$(MAKE) -C $(DJVUDIR)/build
	test -d $(LIBDIR) || mkdir $(LIBDIR)
	cp -a $(DJVULIBDIR)/libdjvulibre.so* $(LIBDIR)

$(CRENGINELIBS):
	cd $(KPVCRLIBDIR) && rm -rf CMakeCache.txt CMakeFiles && \
		CFLAGS="$(CFLAGS)" CXXFLAGS="$(CXXFLAGS)" CC="$(CC)" CXX="$(CXX)" LDFLAGS="$(LDFLAGS)" cmake . && \
		$(MAKE)

$(LUALIB):
ifdef EMULATE_READER
	$(MAKE) -C $(LUADIR) BUILDMODE=static
else
	# To recap: build its TARGET_CC from CROSS+CC, so we need HOSTCC in CC. Build its HOST/TARGET_CFLAGS based on CFLAGS, so we need a neutral CFLAGS without arch
	$(MAKE) -C $(LUADIR) BUILDMODE=static CC="$(HOSTCC)" HOST_CC="$(HOSTCC) -m32" CFLAGS="$(BASE_CFLAGS)" HOST_CFLAGS="$(HOSTCFLAGS)" TARGET_CFLAGS="$(CFLAGS)" CROSS="$(CHOST)-" TARGET_FLAGS="-DLUAJIT_NO_LOG2 -DLUAJIT_NO_EXP2"
endif

$(POPENNSLIB):
	$(MAKE) -C $(POPENNSDIR) CC="$(CC)" AR="$(AR)"

$(K2PDFOPTLIB):
	$(MAKE) -C $(K2PDFOPTLIBDIR) BUILDMODE=shared CC="$(CC)" CFLAGS="$(KOPT_CFLAGS)" AR="$(AR)" all
	test -d $(LIBDIR) || mkdir $(LIBDIR)
	cp -a $(K2PDFOPTLIBDIR)/libk2pdfopt.so* $(LIBDIR)

thirdparty: $(MUPDFLIBS) $(THIRDPARTYLIBS) $(LUALIB) $(DJVULIBS) $(CRENGINELIBS) $(POPENNSLIB) $(K2PDFOPTLIB)

INSTALL_DIR=kindlepdfviewer

LUA_FILES=reader.lua

customupdate: all
	# ensure that the binaries were built for ARM
	file kpdfview | grep ARM || exit 1
	file extr | grep ARM || exit 1
	$(STRIP) --strip-unneeded kpdfview extr
	rm -f kindlepdfviewer-$(VERSION).zip
	rm -rf $(INSTALL_DIR)
	mkdir -p $(INSTALL_DIR)/{history,screenshots,clipboard,libs}
	cp -p README.md COPYING kpdfview extr kpdf.sh $(LUA_FILES) $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/data
	cp -L libs/libdjvulibre.so.21 $(INSTALL_DIR)/libs
	$(STRIP) --strip-unneeded $(INSTALL_DIR)/libs/*
	cp -rpL data/*.css $(INSTALL_DIR)/data
	cp -rpL fonts $(INSTALL_DIR)
	cp -r git-rev resources $(INSTALL_DIR)
	cp -rpL frontend $(INSTALL_DIR)
	mkdir $(INSTALL_DIR)/fonts/host
	zip -9 -r kindlepdfviewer-$(VERSION).zip $(INSTALL_DIR) launchpad/ kite/
	rm -rf $(INSTALL_DIR)
	@echo "copy kindlepdfviewer-$(VERSION).zip to /mnt/us/customupdates and install with shift+shift+I"
