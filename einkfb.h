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

#ifdef EMULATE_READER
#include <SDL.h>
struct fb_var_screeninfo {
    uint32_t xres;
    uint32_t yres;
};
#else
#include <linux/fb.h>
#include "include/einkfb.h"
#include "include/mxcfb.h"
#endif

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "blitbuffer.h"

typedef struct FBInfo {
	int fd;
	BlitBuffer *buf;
	BlitBuffer *real_buf;
#ifdef EMULATE_READER
	SDL_Surface *screen;
#else
	struct fb_fix_screeninfo finfo;
#endif
	struct fb_var_screeninfo vinfo;
} FBInfo;

int luaopen_einkfb(lua_State *L);

#endif
