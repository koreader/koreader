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

#include "einkfb.h"

static int openFrameBuffer(lua_State *L) {
	const char *fb_device = luaL_checkstring(L, 1);
	FBInfo *fb = (FBInfo*) lua_newuserdata(L, sizeof(FBInfo));
	uint8_t *fb_map_address = NULL;

	luaL_getmetatable(L, "einkfb");

	fb->buf = (BlitBuffer*) lua_newuserdata(L, sizeof(BlitBuffer));

	luaL_getmetatable(L, "blitbuffer");
	lua_setmetatable(L, -2);

	lua_setfield(L, -2, "bb");
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

	if (fb->vinfo.xres <= 0 || fb->vinfo.yres <= 0) {
		return luaL_error(L, "invalid resolution %dx%d.\n",
				fb->vinfo.xres, fb->vinfo.yres);
	}

	/* mmap the framebuffer */
	fb->buf->pitch = fb->finfo.line_length;
	fb_map_address = mmap(0, fb->finfo.smem_len,
			PROT_READ | PROT_WRITE, MAP_SHARED, fb->fd, 0);
	if(fb->buf->data == MAP_FAILED) {
		return luaL_error(L, "cannot mmap framebuffer");
	}
	if (fb->vinfo.bits_per_pixel != 4) {
		/* for 8bpp K4, we create a shadow 4bpp blitbuffer 
		 * K4 uses 16 scale 8bpp framebuffer, so we still cheat it as 4bpp */
		fb->buf->pitch = fb->buf->pitch / 2;

		fb->buf->data = malloc(fb->buf->pitch * fb->vinfo.yres);
		if (!fb->buf->data) {
			return luaL_error(L, "failed to allocate memory for framebuffer's shadow blitbuffer!");
		}
		fb->buf->allocated = 1;

		fb->real_buf = (BlitBuffer *)malloc(sizeof(BlitBuffer));
		if (!fb->buf->data) {
			return luaL_error(L, "failed to allocate memory for framebuffer's blitbuffer!");
		}
		fb->real_buf->pitch = fb->finfo.line_length;
		fb->real_buf->w = fb->vinfo.xres;
		fb->real_buf->h = fb->vinfo.yres;
		fb->real_buf->allocated = 0;
		fb->real_buf->data = fb_map_address;
	} else {
		/* for K2, K3 and DXG, we map framebuffer to fb->buf->data directly */
		fb->real_buf = NULL;
		fb->buf->data = fb_map_address;
	}
	memset(fb->buf->data, 0, fb->buf->pitch * fb->buf->h);
#else
	if(SDL_Init(SDL_INIT_VIDEO) < 0) {
		return luaL_error(L, "cannot initialize SDL.");
	}
	if(!(fb->screen = SDL_SetVideoMode(EMULATE_READER_W, EMULATE_READER_H, 32, SDL_HWSURFACE))) {
		return luaL_error(L, "can't get video surface %dx%d for 32bpp.",
				EMULATE_READER_W, EMULATE_READER_H);
	}
	fb->vinfo.xres = EMULATE_READER_W;
	fb->vinfo.yres = EMULATE_READER_H;
	fb->buf->pitch = (EMULATE_READER_W + 1) / 2;
	fb->buf->data = calloc(fb->buf->pitch * EMULATE_READER_H, sizeof(char));
	if(fb->buf->data == NULL) {
		return luaL_error(L, "cannot get framebuffer emu memory");
	}
#endif
	fb->buf->w = fb->vinfo.xres;
	fb->buf->h = fb->vinfo.yres;
	fb->buf->allocated = 0;
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
	// should be save if called twice
	if(fb->buf != NULL && fb->buf->data != NULL) {
#ifndef EMULATE_READER
		if (fb->vinfo.bits_per_pixel != 4) {
			munmap(fb->real_buf->data, fb->finfo.smem_len);
			free(fb->buf->data);
		} else {
			munmap(fb->buf->data, fb->finfo.smem_len);
		}
		close(fb->fd);
#else
		free(fb->buf->data);
#endif
		fb->buf->data = NULL;
		// the blitbuffer in fb->buf should be freed
		// by the Lua GC when our object is garbage
		// collected sice it is visible as an entry
		// in the fb table
	}
	return 0;
}

static int einkUpdate(lua_State *L) {
	FBInfo *fb = (FBInfo*) luaL_checkudata(L, 1, "einkfb");
	// for Kindle e-ink display
	int fxtype = luaL_optint(L, 2, 0);
#ifndef EMULATE_READER
	int i = 0, j = 0, h = 0, w = 0, pitch = 0;
	uint8_t *fb_buf = NULL;

	/* copy bitmap from 4bpp shadow blitbuffer to framebuffer */
	if (fb->vinfo.bits_per_pixel != 4) {
		fb_buf = fb->buf->data;
		h = fb->buf->h;
		w = fb->buf->w;
		pitch = fb->buf->pitch;

		for (i = (h-1); i > 0; i--) {
			for (j = (w-1)/2; j > 0; j--) {
				fb->real_buf->data[i*w + j*2] = fb_buf[i*pitch + j];
				fb->real_buf->data[i*w + j*2] &= 0xF0;
				fb->real_buf->data[i*w + j*2] |= fb_buf[i*pitch + j]>>4 & 0x0F;

				fb->real_buf->data[i*w + j*2 + 1] = fb_buf[i*pitch + j];
				fb->real_buf->data[i*w + j*2 + 1] &= 0x0F;
				fb->real_buf->data[i*w + j*2 + 1] |= fb_buf[i*pitch + j]<<4 & 0xF0;
			}
		}
	}

	update_area_t myarea;
	myarea.x1 = luaL_optint(L, 3, 0);
	myarea.y1 = luaL_optint(L, 4, 0);
	myarea.x2 = myarea.x1 + luaL_optint(L, 5, fb->vinfo.xres);
	myarea.y2 = myarea.y1 + luaL_optint(L, 6, fb->vinfo.yres);
	myarea.buffer = NULL;
	myarea.which_fx = fxtype ? fx_update_partial : fx_update_full;
	ioctl(fb->fd, FBIO_EINK_UPDATE_DISPLAY_AREA, &myarea);
#else
	// for now, we only do fullscreen blits in emulation mode
	if (fxtype == 0) {
		// simmulate a full screen update in eink screen
		if(SDL_MUSTLOCK(fb->screen) && (SDL_LockSurface(fb->screen) < 0)) {
			return luaL_error(L, "can't lock surface.");
		}
		SDL_FillRect(fb->screen, NULL, 0x000000);
		if(SDL_MUSTLOCK(fb->screen)) SDL_UnlockSurface(fb->screen);
		SDL_Flip(fb->screen);
	}

	if(SDL_MUSTLOCK(fb->screen) && (SDL_LockSurface(fb->screen) < 0)) {
		return luaL_error(L, "can't lock surface.");
	}
	int x1 = luaL_optint(L, 3, 0);
	int y1 = luaL_optint(L, 4, 0);
	int w = luaL_optint(L, 5, fb->vinfo.xres);
	int h = luaL_optint(L, 6, fb->vinfo.yres);

	int x, y;

	for(y = y1; y < y1+h; y++) {
		uint32_t *sfptr = (uint32_t*)(fb->screen->pixels + y*fb->screen->pitch);
		for(x = x1; x < x1+w; x+=2) {
			uint8_t value = fb->buf->data[y*fb->buf->pitch + x/2];
			sfptr[x] = SDL_MapRGB(fb->screen->format,
					255 - (value & 0xF0),
					255 - (value & 0xF0),
					255 - (value & 0xF0));
			sfptr[x+1] = SDL_MapRGB(fb->screen->format,
					255 - ((value & 0x0F) << 4),
					255 - ((value & 0x0F) << 4),
					255 - ((value & 0x0F) << 4));
		}
	}
	if(SDL_MUSTLOCK(fb->screen)) SDL_UnlockSurface(fb->screen);
	SDL_Flip(fb->screen);
#endif
	return 0;
}

/* NOTICE!!! You must close and reopen framebuffer after called this method.
 * Otherwise, screen resolution will not be updated! */
static int einkSetOrientation(lua_State *L) {
#ifndef EMULATE_READER
	FBInfo *fb = (FBInfo*) luaL_checkudata(L, 1, "einkfb");
	int mode = luaL_optint(L, 2, 0);

	if (mode < 0 || mode > 3) {
		return luaL_error(L, "Wrong rotation mode %d given!", mode);
	}

	/* ioctl has a different definition for rotation mode.
	 *	          1
	 *	   +--------------+
	 *	   | +----------+ |
	 *	   | |          | |
	 *	   | | Freedom! | |
	 *	   | |          | |  
	 *	   | |          | |  
	 *	 3 | |          | | 2
	 *	   | |          | |
	 *	   | |          | |
	 *	   | +----------+ |
	 *	   |              |
	 *	   |              |
	 *	   +--------------+
	 *	          0
	 * */
	if (mode == 1) 
		mode = 2;
	else if (mode == 2)
		mode = 1;

	ioctl(fb->fd, FBIO_EINK_SET_DISPLAY_ORIENTATION, mode);
#endif
	return 0;
}

static int einkGetOrientation(lua_State *L) {
	int mode = 0;
#ifndef EMULATE_READER
	FBInfo *fb = (FBInfo*) luaL_checkudata(L, 1, "einkfb");

	ioctl(fb->fd, FBIO_EINK_GET_DISPLAY_ORIENTATION, &mode);

	/* adjust ioctl's rotate mode definition to KPV's 
	 * refer to screen.lua */
	if (mode == 2)
		mode = 1;
	else if (mode == 1)
		mode = 2;
#endif
	lua_pushinteger(L, mode);
	return 1;
}


static const struct luaL_Reg einkfb_func[] = {
	{"open", openFrameBuffer},
	{NULL, NULL}
};

static const struct luaL_Reg einkfb_meth[] = {
	{"close", closeFrameBuffer},
	{"__gc", closeFrameBuffer},
	{"refresh", einkUpdate},
	{"getOrientation", einkGetOrientation},
	{"setOrientation", einkSetOrientation},
	{"getSize", getSize},
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
