# you can probably leave these settings alone:

LUADIR=lua
MUPDFDIR=mupdf
MUPDFTARGET=build/debug
MUPDFLIBDIR=$(MUPDFDIR)/$(MUPDFTARGET)
DJVUDIR=djvulibre
CRENGINEDIR=crengine

FREETYPEDIR=$(MUPDFDIR)/thirdparty/freetype-2.4.8
LFSDIR=luafilesystem

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
			$(CRENGINEDIR)/thirdparty/libjpeg/libjpeg.a \
			$(CRENGINEDIR)/thirdparty/zlib/libz.a \
			$(CRENGINEDIR)/thirdparty/antiword/libantiword.a
THIRDPARTYLIBS := $(MUPDFLIBDIR)/libfreetype.a \
			$(MUPDFLIBDIR)/libopenjpeg.a \
			$(MUPDFLIBDIR)/libjbig2dec.a \
			$(MUPDFLIBDIR)/libz.a

# @TODO the libjpeg used by mupdf is too new for crengine and will cause
# a segment fault when decoding jpeg images in crengine, we need to fix 
# this. 28.03 2012 (houqp)
			#$(MUPDFLIBDIR)/libjpeg.a

LUALIB := $(LUADIR)/src/liblua.a

kpdfview: kpdfview.o einkfb.o pdf.o blitbuffer.o drawcontext.o input.o util.o ft.o lfs.o $(MUPDFLIBS) $(THIRDPARTYLIBS) $(LUALIB) djvu.o $(DJVULIBS) cre.o $(CRENGINELIBS)
	$(CC) -lm -ldl -lpthread $(EMU_LDFLAGS) -lstdc++  \
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
	grep USE_FONTCONFIG $(CRENGINEDIR)/crengine/include/crsetup.h && grep -v USE_FONTCONFIG $(CRENGINEDIR)/crengine/include/crsetup.h > /tmp/new && mv /tmp/new $(CRENGINEDIR)/crengine/include/crsetup.h
	test -f $(CRENGINEDIR)/thirdparty/zlib/qconfig.h || touch $(CRENGINEDIR)/thirdparty/zlib/qconfig.h
	test -f mupdf-thirdparty.zip || wget http://www.mupdf.com/download/mupdf-thirdparty.zip
	unzip mupdf-thirdparty.zip -d mupdf
	test -f lua-5.1.4.tar.gz || wget http://www.lua.org/ftp/lua-5.1.4.tar.gz
	tar xvzf lua-5.1.4.tar.gz && ln -s lua-5.1.4 lua

clean:
	-rm -f *.o kpdfview

cleanthirdparty:
	make -C $(LUADIR) clean
	make -C $(MUPDFDIR) clean
	make -C $(CRENGINEDIR) clean
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
	cd $(DJVUDIR)/build && ../configure --disable-desktopfiles --disable-shared --enable-static --host=$(HOST)
endif
	make -C $(DJVUDIR)/build

$(CRENGINELIBS):
	cd $(CRENGINEDIR) && cmake -D CR3_PNG=1 -D CR3_JPEG=1 .
	cd $(CRENGINEDIR)/thirdparty/libjpeg && make
	cd $(CRENGINEDIR)/thirdparty/chmlib && make
	cd $(CRENGINEDIR)/thirdparty/antiword && make
	cd $(CRENGINEDIR)/thirdparty/libpng && make
	cd $(CRENGINEDIR)/thirdparty/zlib && make
	cd $(CRENGINEDIR)/crengine && make

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
	cp -p README.TXT COPYING kpdfview *.lua $(INSTALL_DIR)
	zip -r kindlepdfviewer-$(VERSION).zip $(INSTALL_DIR) launchpad/
	rm -Rf $(INSTALL_DIR)
	@echo "copy kindlepdfviewer-$(VERSION).zip to /mnt/us/customupdates and install with shift+shift+I"
