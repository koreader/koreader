/*
    KindlePDFViewer: eink framebuffer access
    Copyright (C) 2011 Hans-Werner Hilse <hilse@web.de>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
#ifndef _PDF_EINKFB_H
#define _PDF_EINKFB_H

#include <linux/fb.h>
#ifdef EMULATE_EINKFB
#include <stdlib.h>
//#define EMULATE_EINKFB_W 824
//#define EMULATE_EINKFB_H 1200
//#define EMULATE_EINKFB_FILE "/tmp/displayfifo"
#else
#include "include/einkfb.h"
#endif

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

typedef struct FBInfo {
	int fd;
	void *data;
	struct fb_fix_screeninfo finfo;
	struct fb_var_screeninfo vinfo;
} FBInfo;

int luaopen_einkfb(lua_State *L);

#endif
