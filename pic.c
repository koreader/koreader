/*
    KindlePDFViewer: Picture viewer abstraction for Lua
    Copyright (C) 2012 Tigran Aivazian <tigran@bibles.org.uk>

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

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>

#include "blitbuffer.h"
#include "drawcontext.h"
#include "pic.h"
#include "pic_jpeg.h"

#define MIN(a, b)      ((a) < (b) ? (a) : (b))
#define MAX(a, b)      ((a) > (b) ? (a) : (b))

typedef struct PicDocument {
	int width;
	int height;
	int components;
	uint8_t *image;
} PicDocument;

typedef struct PicPage {
	int width;
	int height;
	uint8_t *image;
	PicDocument *doc;
} PicPage;

/* Uses luminance match for approximating the human perception of colour,
 * as per http://en.wikipedia.org/wiki/Grayscale#Converting_color_to_grayscale
 * L = 0.299*Red + 0.587*Green + 0.114*Blue */
static uint8_t *rgbToGrayscale(uint8_t *image, int width, int height)
{
	int x, y;
	uint8_t *buf = malloc(width*height+1);

	if (!buf) return NULL;

	for (x = 0; x<width; x++)
		for (y=0; y<height; y++) {
			int pos = 3*(x+y*width);
			buf[x+y*width] = (uint8_t)(0.299*((double)image[pos]) + 0.587*((double)image[pos+1]) + 0.114*((double)image[pos+2]));
		}

	return buf;
}

static int openDocument(lua_State *L) {
	int width, height, components;
	const char *filename = luaL_checkstring(L, 1);

	PicDocument *doc = (PicDocument*) lua_newuserdata(L, sizeof(PicDocument));
	luaL_getmetatable(L, "picdocument");
	lua_setmetatable(L, -2);

	uint8_t *raw_image = jpegLoadFile(filename, &width, &height, &components);
	if (!raw_image)
		return luaL_error(L, "Cannot open jpeg file");

	doc->image = NULL;
	if (components == 1)
		doc->image = raw_image;
	else if (components == 3) {
		uint8_t *gray_image = rgbToGrayscale(raw_image, width, height);
		free(raw_image);
		if (!gray_image)
			return luaL_error(L, "Cannot convert to grayscale");
		else
			doc->image = gray_image;
	} else {
		free(raw_image);
		return luaL_error(L, "Unsupported image format");
	}

	doc->width = width;
	doc->height = height;
	doc->components = components;
	return 1;
}

static int openPage(lua_State *L) {
	PicDocument *doc = (PicDocument*) luaL_checkudata(L, 1, "picdocument");
	//int pageno = luaL_checkint(L, 2);

	PicPage *page = (PicPage*) lua_newuserdata(L, sizeof(PicPage));
	luaL_getmetatable(L, "picpage");
	lua_setmetatable(L, -2);

	page->width = doc->width;
	page->height = doc->height;
	page->image = doc->image;
	page->doc = doc;

	return 1;
}

static int getNumberOfPages(lua_State *L) {
	lua_pushinteger(L, 1);
	return 1;
}

static int getOriginalPageSize(lua_State *L) {
	PicDocument *doc = (PicDocument*) luaL_checkudata(L, 1, "picdocument");
	lua_pushnumber(L, doc->width);
	lua_pushnumber(L, doc->height);
	lua_pushnumber(L, doc->components);
	return 3;
}

/* re-entrant */
static int closeDocument(lua_State *L) {
	PicDocument *doc = (PicDocument*) luaL_checkudata(L, 1, "picdocument");
	if (doc->image != NULL) {
		free(doc->image);
		doc->image = NULL;
	}
	return 0;
}

/* uses very simple nearest neighbour scaling */
static void scaleImage(uint8_t *result, uint8_t *image, int width, int height, int new_width, int new_height)
{
	int x, y;

	for (x = 0; x<new_width; x++)
		for (y=0; y<new_height; y++)
			result[x+y*new_width] = image[(x*width/new_width) + (y*height/new_height)*width];
}

static int drawPage(lua_State *L) {
	PicPage *page = (PicPage*) luaL_checkudata(L, 1, "picpage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 3, "blitbuffer");
	int x_offset = MAX(0, dc->offset_x);
	int y_offset = MAX(0, dc->offset_y);
	int x, y;
	int img_width = page->width;
	int img_height = page->height;
	int img_new_width = bb->w;
	int img_new_height = bb->h;
	unsigned char adjusted_low[16], adjusted_high[16];
	int i, adjust_pixels = 0;

	/* prepare the tables for adjusting the intensity of pixels */
	if (dc->gamma != -1.0) {
		for (i=0; i<16; i++) {
			adjusted_low[i] = MIN(15, (unsigned char)floorf(dc->gamma * (float)i));
			adjusted_high[i] = adjusted_low[i] << 4;
		}
		adjust_pixels = 1;
	}

	uint8_t *scaled_image = malloc(img_new_width*img_new_height+1);
	if (!scaled_image)
		return 0;

	scaleImage(scaled_image, page->image, img_width, img_height, img_new_width, img_new_height);

	uint8_t *bbptr = bb->data;
	uint8_t *pmptr = scaled_image;
	bbptr += bb->pitch * y_offset;
	for(y = y_offset; y < img_new_height; y++) {
		for(x = x_offset/2; x < (img_new_width / 2); x++) {
			int p = x*2 - x_offset;
			unsigned char low = 15 - (pmptr[p + 1] >> 4);
			unsigned char high = 15 - (pmptr[p] >> 4);
			if (adjust_pixels)
				bbptr[x] = adjusted_high[high] | adjusted_low[low];
			else
				bbptr[x] = (high << 4) | low;
		}
		if (img_new_width & 1)
			bbptr[x] = 255 - (pmptr[x*2] & 0xF0);
		bbptr += bb->pitch;
		pmptr += img_new_width;
	}

	free(scaled_image);
	return 0;
}

static int getCacheSize(lua_State *L) {
	PicDocument *doc = (PicDocument*) luaL_checkudata(L, 1, "picdocument");
	lua_pushnumber(L, 0);
	return 1;
}

static int cleanCache(lua_State *L) {
	return 0;
}

static int getPageSize(lua_State *L) {
	PicPage *page = (PicPage*) luaL_checkudata(L, 1, "picpage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	
	lua_pushnumber(L, dc->zoom * page->width);
	lua_pushnumber(L, dc->zoom * page->height);

	return 2;
}


static int closePage(lua_State *L) {
	//PicPage *page = (PicPage*) luaL_checkudata(L, 1, "picpage");
	return 0;
}

/* unsupported so fake it */
static int getUsedBBox(lua_State *L) {
	lua_pushnumber(L, (double)0.01);
	lua_pushnumber(L, (double)0.01);
	lua_pushnumber(L, (double)-0.01);
	lua_pushnumber(L, (double)-0.01);
	return 4;
}

static int getTableOfContent(lua_State *L) {
	lua_newtable(L);
	return 1;
}

static const struct luaL_Reg pic_func[] = {
	{"openDocument", openDocument},
	{NULL, NULL}
};

static const struct luaL_Reg picdocument_meth[] = {
	{"openPage", openPage},
	{"getPages", getNumberOfPages},
	{"getToc", getTableOfContent},
	{"getOriginalPageSize", getOriginalPageSize},
	{"getCacheSize", getCacheSize},
	{"close", closeDocument},
	{"cleanCache", cleanCache},
	{"__gc", closeDocument},
	{NULL, NULL}
};


static const struct luaL_Reg picpage_meth[] = {
	{"getSize", getPageSize},
	{"getUsedBBox", getUsedBBox},
	{"close", closePage},
	{"__gc", closePage},
	{"draw", drawPage},
	{NULL, NULL}
};


int luaopen_pic(lua_State *L) {
	luaL_newmetatable(L, "picdocument");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, picdocument_meth);
	lua_pop(L, 1);

	luaL_newmetatable(L, "picpage");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, picpage_meth);
	lua_pop(L, 1);

	luaL_register(L, "pic", pic_func);
	return 1;
}
