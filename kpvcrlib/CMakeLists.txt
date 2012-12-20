
PROJECT(kpvcrlib)
cmake_minimum_required(VERSION 2.6)

SET(MUPDF_DIR ../mupdf)
SET(MUPDF_3RDPARTY_DIR ${MUPDF_DIR}/thirdparty)
SET(CR_3RDPARTY_DIR crengine/thirdparty)
SET(CRE_DIR crengine/crengine)

SET(CR3_PNG 1)
#SET(CR3_JPEG 1)

SET(FREETYPE_INCLUDE_DIRS ${MUPDF_3RDPARTY_DIR}/freetype/include)
#SET(FREETYPE_INCLUDE_DIRS ${CR_3RDPARTY_DIR}/freetype/include)
SET(ANTIWORD_INCLUDE_DIR ${CR_3RDPARTY_DIR}/antiword)
SET(CHM_INCLUDE_DIRS ${CR_3RDPARTY_DIR}/chmlib)
SET(PNG_INCLUDE_DIR ${CR_3RDPARTY_DIR}/libpng)
SET(ZLIB_INCLUDE_DIR ${MUPDF_3RDPARTY_DIR}/zlib)
#SET(ZLIB_INCLUDE_DIR ${CR_3RDPARTY_DIR}/zlib)
SET(JPEGLIB_INCLUDE_DIR ${MUPDF_3RDPARTY_DIR}/jpeg)
#SET(JPEGLIB_INCLUDE_DIR ${CR_3RDPARTY_DIR}/libjpeg)
SET(JCONFIG_INCLUDE_DIR ${MUPDF_DIR}/scripts)
SET(CREGINE_INCLUDE_DIR ${CRE_DIR}/include)

INCLUDE_DIRECTORIES(
	${JCONFIG_INCLUDE_DIR}
	${FREETYPE_INCLUDE_DIRS}
	${ANTIWORD_INCLUDE_DIR}
	${CHM_INCLUDE_DIRS}
	${PNG_INCLUDE_DIR} 
	${ZLIB_INCLUDE_DIR}
	${JPEGLIB_INCLUDE_DIR}
	${CREGINE_INCLUDE_DIR}
)

ADD_DEFINITIONS(-DLINUX=1 -D_LINUX=1 -DUSE_FONTCONFIG=0 -DUSE_FREETYPE=1 -DCR3_PATCH=1 -DNDEBUG=1)


message("Will build patched LIBCHM library")
ADD_DEFINITIONS(-DCHM_SUPPORT_ENABLED=1)
ADD_SUBDIRECTORY(${CR_3RDPARTY_DIR}/chmlib)

message("Will build patched LIBPNG library")
ADD_SUBDIRECTORY(${CR_3RDPARTY_DIR}/libpng)

#message("Will build patched JPEGLIB library")
#ADD_SUBDIRECTORY(${CR_3RDPARTY_DIR}/libjpeg)

message("Will build patched ANTIWORD library")
ADD_DEFINITIONS(-DENABLE_ANTIWORD=1)
ADD_DEFINITIONS(-DCR3_ANTIWORD_PATCH=1)
ADD_SUBDIRECTORY(${CR_3RDPARTY_DIR}/antiword)

message("Will build crengine library")
#SET(GUI kpv)
#ADD_SUBDIRECTORY(crengine/crengine)

ADD_DEFINITIONS(-DHAVE_PROTOTYPES)
ADD_DEFINITIONS(-DHAVE_UNSIGNED_CHAR)
ADD_DEFINITIONS(-Dmain=xxxmain)
SET (CRENGINE_SOURCES 
	${CRE_DIR}/src/cp_stats.cpp
	${CRE_DIR}/src/lvstring.cpp
	${CRE_DIR}/src/props.cpp
	${CRE_DIR}/src/lstridmap.cpp
	${CRE_DIR}/src/rtfimp.cpp
	${CRE_DIR}/src/lvmemman.cpp
	${CRE_DIR}/src/lvstyles.cpp
	${CRE_DIR}/src/crtxtenc.cpp
	${CRE_DIR}/src/lvtinydom.cpp
	${CRE_DIR}/src/lvstream.cpp
	${CRE_DIR}/src/lvxml.cpp
	${CRE_DIR}/src/chmfmt.cpp
	${CRE_DIR}/src/epubfmt.cpp
	${CRE_DIR}/src/pdbfmt.cpp
	${CRE_DIR}/src/wordfmt.cpp
	${CRE_DIR}/src/lvstsheet.cpp
	${CRE_DIR}/src/txtselector.cpp
	${CRE_DIR}/src/crtest.cpp
	${CRE_DIR}/src/lvbmpbuf.cpp
	${CRE_DIR}/src/lvfnt.cpp
	${CRE_DIR}/src/hyphman.cpp
	${CRE_DIR}/src/lvfntman.cpp
	${CRE_DIR}/src/lvimg.cpp
	${CRE_DIR}/src/crskin.cpp
	${CRE_DIR}/src/lvdrawbuf.cpp
	${CRE_DIR}/src/lvdocview.cpp
	${CRE_DIR}/src/lvpagesplitter.cpp
	${CRE_DIR}/src/lvtextfm.cpp
	${CRE_DIR}/src/lvrend.cpp
	${CRE_DIR}/src/wolutil.cpp
	${CRE_DIR}/src/hist.cpp
	${CRE_DIR}/src/cri18n.cpp
)
ADD_LIBRARY(crengine SHARED ${CRENGINE_SOURCES})

