# you can probably leave these settings alone:

LUADIR=lua
MUPDFDIR=mupdf
MUPDFTARGET=build/debug
MUPDFLIBDIR=$(MUPDFDIR)/$(MUPDFTARGET)
LDFLAGS=-lm -ldl

# set this to your ARM cross compiler:

CC:=arm-unknown-linux-gnueabi-gcc
#CC:=gcc

#ALLCFLAGS:=-g -O0
ALLCFLAGS:=-O2

# you can configure an emulation for the (eink) framebuffer here.
# the application won't use the framebuffer (and the special e-ink ioctls)
# in that case.

EMULATE_EINKFB_FILE=/tmp/displayfifo
#EMULATE_EINKFB_FILE=/dev/null
EMULATE_EINKFB_W=824
EMULATE_EINKFB_H=1200

CFLAGS= $(ALLCFLAGS) -I$(LUADIR)/src -I$(MUPDFDIR)/ \
	-DEMULATE_EINKFB_FILE='"$(EMULATE_EINKFB_FILE)"' \
	-DEMULATE_EINKFB_W=$(EMULATE_EINKFB_W) \
	-DEMULATE_EINKFB_H=$(EMULATE_EINKFB_H)

# comment in the following line if you want to use the framebuffer emulation:

#CFLAGS+= -DEMULATE_EINKFB

# enable tracing output:

#CFLAGS+= -DMUPDF_TRACE

# for now, all dependencies except for the libc are compiled into the final binary:

kpdfview: kpdfview.o einkfb.o pdf.o blitbuffer.o input.o util.o
	$(CC) $(LDFLAGS) \
		kpdfview.o \
		einkfb.o \
		pdf.o \
		blitbuffer.o \
		input.o \
		util.o \
		$(MUPDFLIBDIR)/libmupdf.a \
		$(MUPDFLIBDIR)/libfitz.a \
	       	$(MUPDFLIBDIR)/libfreetype.a \
	       	$(MUPDFLIBDIR)/libjpeg.a \
	       	$(MUPDFLIBDIR)/libopenjpeg.a \
	       	$(MUPDFLIBDIR)/libjbig2dec.a \
	       	$(MUPDFLIBDIR)/libz.a \
		$(LUADIR)/src/liblua.a -o kpdfview

fetchthirdparty:
	-rmdir mupdf
	-rmdir lua
	-rm lua
	git clone git://git.ghostscript.com/mupdf.git
	( cd mupdf ; wget http://www.mupdf.com/download/mupdf-thirdparty.zip && unzip mupdf-thirdparty.zip )
	wget http://www.lua.org/ftp/lua-5.1.4.tar.gz && tar xvzf lua-5.1.4.tar.gz && ln -s lua-5.1.4 lua

clean:
	-rm -f *.o kpdfview

cleanthirdparty:
	make -C lua clean
	make -C mupdf clean

$(MUPDFDIR)/fontdump.host:
	make -C mupdf CC=gcc $(MUPDFTARGET)/fontdump
	cp -a $(MUPDFLIBDIR)/fontdump $(MUPDFDIR)/fontdump.host
	make -C mupdf clean

$(MUPDFDIR)/cmapdump.host:
	make -C mupdf CC=gcc $(MUPDFTARGET)/cmapdump
	cp -a $(MUPDFLIBDIR)/cmapdump $(MUPDFDIR)/cmapdump.host
	make -C mupdf clean

thirdparty: $(MUPDFDIR)/cmapdump.host $(MUPDFDIR)/fontdump.host
	make -C lua/src CC="$(CC)" CFLAGS="$(ALLCFLAGS)" MYCFLAGS=-DLUA_USE_LINUX MYLIBS="-Wl,-E" liblua.a
	# generate cmapdump and fontdump helpers.
	# those need to be run on the build platform, not the target device.
	# thus, we override the CC here.
	make -C mupdf clean
	# build only thirdparty libs, libfitz and pdf utils, which will care for libmupdf.a being built
	CC="$(CC)" CFLAGS="$(ALLCFLAGS)" make -C mupdf CMAPDUMP=cmapdump.host FONTDUMP=fontdump.host MUPDF= XPS_APPS=

install:
	# install to kindle using USB networking
	scp kpdfview reader.lua root@192.168.2.2:/mnt/us/test/

display:
	# run mplayer on a FIFO, fed by using the framebuffer emulation
	# make a FIFO
	[ -p $(EMULATE_EINKFB_FILE) ] || mknod $(EMULATE_EINKFB_FILE) p
	# ...and display from it
	mplayer -rawvideo format=y8:w=$(EMULATE_EINKFB_W):h=$(EMULATE_EINKFB_H) -demuxer rawvideo $(EMULATE_EINKFB_FILE)
