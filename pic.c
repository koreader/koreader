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
#include "blitbuffer.h"
#include "drawcontext.h"
#include "pic.h"

typedef struct PicDocument {
	int width, height;
} PicDocument;

typedef struct PicPage {
	int width, height;
	PicDocument *doc;
} PicPage;

static int openDocument(lua_State *L) {
	const char *filename = luaL_checkstring(L, 1);
	printf("openDocument(%s)\n", filename);

	PicDocument *doc = (PicDocument*) lua_newuserdata(L, sizeof(PicDocument));
	luaL_getmetatable(L, "picdocument");
	lua_setmetatable(L, -2);

	doc->width = 600;
	doc->height = 800;
	return 1;
}

static int openPage(lua_State *L) {
	PicDocument *doc = (PicDocument*) luaL_checkudata(L, 1, "picdocument");
	int pageno = luaL_checkint(L, 2);
	printf("openPage(%d)\n", pageno);

	PicPage *page = (PicPage*) lua_newuserdata(L, sizeof(PicPage));
	luaL_getmetatable(L, "picpage");
	lua_setmetatable(L, -2);
	page->width = doc->width;
	page->height = doc->height;
	page->doc = doc;

	return 1;
}

static const struct luaL_Reg pic_func[] = {
	{"openDocument", openDocument},
	{NULL, NULL}
};

static int getNumberOfPages(lua_State *L) {
	lua_pushinteger(L, 1);
	return 1;
}

static int getOriginalPageSize(lua_State *L) {
	PicDocument *doc = (PicDocument*) luaL_checkudata(L, 1, "picdocument");
	lua_pushnumber(L, doc->width);
	lua_pushnumber(L, doc->height);
	return 2;
}

static int closeDocument(lua_State *L) {
	PicDocument *doc = (PicDocument*) luaL_checkudata(L, 1, "picdocument");
	return 0;
}

static int drawPage(lua_State *L) {
	printf("drawPage()\n");
	PicPage *page = (PicPage*) luaL_checkudata(L, 1, "picpage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 3, "blitbuffer");
	uint8_t *imagebuffer = malloc((bb->w)*(bb->h)+1);
	
	/* fill pixel map with white color */
	memset(imagebuffer, 0xFF, (bb->w)*(bb->h)+1);
	free(imagebuffer);
	return 0;
}

static int getCacheSize(lua_State *L) {
	lua_pushnumber(L, 8192);
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
	PicPage *page = (PicPage*) luaL_checkudata(L, 1, "picpage");
	printf("closePage()\n");
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

static const struct luaL_Reg picdocument_meth[] = {
	{"openPage", openPage},
	{"getPages", getNumberOfPages},
	{"getOriginalPageSize", getOriginalPageSize},
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
