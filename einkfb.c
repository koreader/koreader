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
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <fcntl.h>
//#include <stdio.h>
#include "blitbuffer.h"

#include "einkfb.h"

static int openFrameBuffer(lua_State *L) {
	const char *fb_device = luaL_checkstring(L, 1);
	FBInfo *fb = (FBInfo*) lua_newuserdata(L, sizeof(FBInfo));

	luaL_getmetatable(L, "einkfb");
	lua_setmetatable(L, -2);

#ifndef EMULATE_READER
	/* open framebuffer */
	fb->fd = open(fb_device, O_RDWR);
	if (fb->fd == -1) {
		return luaL_error(L, "cannot open framebuffer %s",
				fb_device);
	}

	/* initialize data structures */
	memset(&fb->finfo, 0, sizeof(fb->finfo));
	memset(&fb->vinfo, 0, sizeof(fb->vinfo));

	/* Get fixed screen information */
	if (ioctl(fb->fd, FBIOGET_FSCREENINFO, &fb->finfo)) {
		return luaL_error(L, "cannot get screen info");
	}

	if (fb->finfo.type != FB_TYPE_PACKED_PIXELS) {
		return luaL_error(L, "video type %x not supported",
				fb->finfo.type);
	}

	if (ioctl(fb->fd, FBIOGET_VSCREENINFO, &fb->vinfo)) {
		return luaL_error(L, "cannot get variable screen info");
	}

	if (!fb->vinfo.grayscale) {
		return luaL_error(L, "only grayscale is supported but framebuffer says it isn't");
	}

	if (fb->vinfo.bits_per_pixel != 4) {
		return luaL_error(L, "only 4bpp is supported for now, got %d bpp",
				fb->vinfo.bits_per_pixel);
	}

	if (fb->vinfo.xres <= 0 || fb->vinfo.yres <= 0) {
		return luaL_error(L, "invalid resolution %dx%d.\n",
				fb->vinfo.xres, fb->vinfo.yres);
	}

	/* mmap the framebuffer */
	fb->data = mmap(0, fb->finfo.smem_len,
			PROT_READ | PROT_WRITE, MAP_SHARED, fb->fd, 0);
	if(fb->data == MAP_FAILED) {
		return luaL_error(L, "cannot mmap framebuffer");
	}
#else
	if(SDL_Init(SDL_INIT_VIDEO) < 0) {
		return luaL_error(L, "cannot initialize SDL.");
	}
	if(!(fb->screen = SDL_SetVideoMode(EMULATE_READER_W, EMULATE_READER_H, 32, SDL_HWSURFACE))) {
		return luaL_error(L, "can't get video surface %dx%d for 32bpp.",
				EMULATE_READER_W, EMULATE_READER_H);
	}
	memset(&fb->finfo, 0, sizeof(fb->finfo));
	memset(&fb->vinfo, 0, sizeof(fb->vinfo));
	fb->vinfo.xres = EMULATE_READER_W;
	fb->vinfo.yres = EMULATE_READER_H;
	fb->vinfo.grayscale = 1;
	fb->vinfo.bits_per_pixel = 4;
	fb->finfo.smem_len = EMULATE_READER_W * EMULATE_READER_H / 2;
	fb->finfo.line_length = EMULATE_READER_W / 2;
	fb->finfo.type = FB_TYPE_PACKED_PIXELS;
	fb->data = malloc(fb->finfo.smem_len);
#endif

	return 1;
}

static int getSize(lua_State *L) {
	FBInfo *fb = (FBInfo*) luaL_checkudata(L, 1, "einkfb");
	lua_pushinteger(L, fb->vinfo.xres);
	lua_pushinteger(L, fb->vinfo.yres);
	return 2;
}

static int closeFrameBuffer(lua_State *L) {
	FBInfo *fb = (FBInfo*) luaL_checkudata(L, 1, "einkfb");
#ifndef EMULATE_READER
	munmap(fb->data, fb->finfo.smem_len);
	close(fb->fd);
#else
	free(fb->data);
#endif
	return 0;
}

static int blitFullToFrameBuffer(lua_State *L) {
	FBInfo *fb = (FBInfo*) luaL_checkudata(L, 1, "einkfb");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 2, "blitbuffer");

	if(bb->w != fb->vinfo.xres || bb->h != fb->vinfo.yres) {
		return luaL_error(L, "blitbuffer size must be framebuffer size!");
	}
	
	uint8_t *fbptr = (uint8_t*)fb->data;
	uint32_t *bbptr = (uint32_t*)bb->data;

	int c = fb->vinfo.xres * fb->vinfo.yres / 2;

	while(c--) {
		*fbptr = (((*bbptr & 0x00F00000) >> 20) | (*bbptr & 0x000000F0)) ^ 0xFF;
		fbptr++;
		bbptr++;
	}
	return 0;
}

static int blitToFrameBuffer(lua_State *L) {
	FBInfo *fb = (FBInfo*) luaL_checkudata(L, 1, "einkfb");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 2, "blitbuffer");
	int xdest = luaL_checkint(L, 3) & 0x7FFFFFFE;
	int ydest = luaL_checkint(L, 4);
	int xoffs = luaL_checkint(L, 5) & 0x7FFFFFFE;
	int yoffs = luaL_checkint(L, 6);
	int w = luaL_checkint(L, 7);
	int h = luaL_checkint(L, 8);
	int x, y;

	// check bounds
	if(yoffs >= bb->h) {
		return 0;
	} else if(yoffs + h > bb->w) {
		h = bb->h - yoffs;
	}
	if(ydest >= fb->vinfo.yres) {
		return 0;
	} else if(ydest + h > fb->vinfo.yres) {
		h = fb->vinfo.yres - ydest;
	}
	if(xoffs >= bb->w) {
		return 0;
	} else if(xoffs + w > bb->w) {
		w = bb->w - xoffs;
	}
	if(xdest >= fb->vinfo.xres) {
		return 0;
	} else if(xdest + w > fb->vinfo.xres) {
		w = fb->vinfo.xres - xdest;
	}

	w = (w+1) / 2; // we'll always do two pixels at once for now

	uint8_t *fbptr = (uint8_t*)(fb->data + 
			ydest * fb->finfo.line_length + 
			xdest / 2);
	uint32_t *bbptr = (uint32_t*)(bb->data +
			yoffs * bb->w * BLITBUFFER_BYTESPP +
			xoffs * BLITBUFFER_BYTESPP);

	for(y = 0; y < h; y++) {
		for(x = 0; x < w; x++) {
			fbptr[x] = (((bbptr[x] & 0x00F00000) >> 20) | (bbptr[x] & 0x000000F0)) ^ 0xFF;
		}
		fbptr += fb->finfo.line_length;
		bbptr += (bb->w / 2);
	}
	return 0;
}

static int einkUpdate(lua_State *L) {
	FBInfo *fb = (FBInfo*) luaL_checkudata(L, 1, "einkfb");
	// for Kindle e-ink display
	int fxtype = luaL_optint(L, 2, 0);
#ifndef EMULATE_READER
	update_area_t myarea;
	myarea.x1 = luaL_optint(L, 3, 0);
	myarea.y1 = luaL_optint(L, 4, 0);
	myarea.x2 = luaL_optint(L, 5, fb->vinfo.xres);
	myarea.y2 = luaL_optint(L, 6, fb->vinfo.yres);
	myarea.buffer = NULL;
	myarea.which_fx = fxtype ? fx_update_partial : fx_update_full;
	ioctl(fb->fd, FBIO_EINK_UPDATE_DISPLAY_AREA, &myarea);
#else
	// for now, we only do fullscreen blits in emulation mode
	if(SDL_MUSTLOCK(fb->screen) && (SDL_LockSurface(fb->screen) < 0)) {
		return luaL_error(L, "can't lock surface.");
	}
	uint32_t *sfptr = (uint32_t*)fb->screen->pixels;
	uint8_t *fbptr = (uint8_t*)fb->data;

	int c = fb->finfo.smem_len;

	while(c--) {
		*sfptr = SDL_MapRGB(fb->screen->format,
				255 - (*fbptr & 0xF0),
				255 - (*fbptr & 0xF0),
				255 - (*fbptr & 0xF0));
		sfptr++;
		*sfptr = SDL_MapRGB(fb->screen->format,
				255 - ((*fbptr & 0x0F) << 4),
				255 - ((*fbptr & 0x0F) << 4),
				255 - ((*fbptr & 0x0F) << 4));
		sfptr++;
		fbptr++;
	}
	if(SDL_MUSTLOCK(fb->screen)) SDL_UnlockSurface(fb->screen);
	SDL_Flip(fb->screen);
#endif
	return 0;
}

static const struct luaL_reg einkfb_func[] = {
	{"open", openFrameBuffer},
	{NULL, NULL}
};

static const struct luaL_reg einkfb_meth[] = {
	{"close", closeFrameBuffer},
	{"refresh", einkUpdate},
	{"getSize", getSize},
	{"blitFrom", blitToFrameBuffer},
	{"blitFullFrom", blitFullToFrameBuffer},
	{NULL, NULL}
};

int luaopen_einkfb(lua_State *L) {
	luaL_newmetatable(L, "einkfb");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, einkfb_meth);
	luaL_register(L, "einkfb", einkfb_func);

	return 1;
}
