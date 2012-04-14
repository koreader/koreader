/*
    KindlePDFViewer: MuPDF abstraction for Lua, only image part
    Copyright (C) 2012 Hans-Werner Hilse <hilse@web.de>

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
#include <fitz/fitz.h>

#include "blitbuffer.h"
#include "mupdfimg.h"
#include <stdio.h>
#include <stddef.h>


typedef struct Image {
	fz_pixmap *pixmap;
	fz_context *context;
} Image;

static int newImage(lua_State *L) {
	int cache_size = luaL_optint(L, 1, 8 << 20); // 8 MB limit default

	Image *img = (Image*) lua_newuserdata(L, sizeof(Image));

	img->pixmap = NULL;

	luaL_getmetatable(L, "image");
	lua_setmetatable(L, -2);

	img->context = fz_new_context(NULL, NULL, cache_size);

	return 1;
}

static int loadPNGData(lua_State *L) {
	Image *img = (Image*) luaL_checkudata(L, 1, "image");
	size_t length;
	unsigned char *data = luaL_checklstring(L, 2, &length);
	fz_try(img->context) {
		img->pixmap = fz_load_png(img->context, data, length);
	}
	fz_catch(img->context) {
		return luaL_error(L, "cannot load PNG data");
	}
}

static int loadJPEGData(lua_State *L) {
	Image *img = (Image*) luaL_checkudata(L, 1, "image");
	size_t length;
	unsigned char *data = luaL_checklstring(L, 2, &length);
	fz_try(img->context) {
		img->pixmap = fz_load_jpeg(img->context, data, length);
	}
	fz_catch(img->context) {
		return luaL_error(L, "cannot open JPEG data");
	}
}

static int toBlitBuffer(lua_State *L) {
	Image *img = (Image*) luaL_checkudata(L, 1, "image");
	BlitBuffer *bb;
	int ret;
	int w, h;

	fz_pixmap *pix;

	if(img->pixmap == NULL) {
		return luaL_error(L, "no pixmap loaded that we could convert");
	}

	if(img->pixmap->n == 2) {
		pix = img->pixmap;
	} else {
		fz_try(img->context) {
			pix = fz_new_pixmap(img->context, fz_device_gray, img->pixmap->w, img->pixmap->h);
		}
		fz_catch(img->context) {
			return luaL_error(L, "can't claim new grayscale fz_pixmap");
		}
		fz_convert_pixmap(img->context, img->pixmap, pix);
	}

	ret = newBlitBufferNative(L, img->pixmap->w, img->pixmap->h, &bb);
	if(ret != 1) {
		// TODO (?): fail more gracefully, clean up mem?
		return ret;
	}

	uint8_t *bbptr = (uint8_t*)bb->data;
	uint16_t *pmptr = (uint16_t*)pix->samples;
	int x, y;

	for(y = 0; y < bb->h; y++) {
		for(x = 0; x < (bb->w / 2); x++) {
			bbptr[x] = (((pmptr[x*2 + 1] & 0xF0) >> 4) | (pmptr[x*2] & 0xF0)) ^ 0xFF;
		}
		if(bb->w & 1) {
			bbptr[x] = (pmptr[x*2] & 0xF0) ^ 0xF0;
		}
		bbptr += bb->pitch;
		pmptr += bb->w;
	}

	if(pix != img->pixmap) {
		fz_drop_pixmap(img->context, pix);
	}

	return 1;
}

static int freeImage(lua_State *L) {
	Image *img = (Image*) luaL_checkudata(L, 1, "image");
	if(img->pixmap) {
		fz_drop_pixmap(img->context, img->pixmap);
	}
	fz_free_context(img->context);
	return 0;
}

static const struct luaL_Reg mupdfimg_func[] = {
	{"new", newImage},
	{NULL, NULL}
};

static const struct luaL_Reg image_meth[] = {
	{"loadPNGData", loadPNGData},
	{"loadJPEGData", loadJPEGData},
	{"toBlitBuffer", toBlitBuffer},
	{"free", freeImage},
	{"__gc", freeImage},
	{NULL, NULL}
};

int luaopen_mupdfimg(lua_State *L) {
	luaL_newmetatable(L, "image");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, image_meth);
	lua_pop(L, 1);
	luaL_register(L, "mupdfimg", mupdfimg_func);
	return 1;
}
