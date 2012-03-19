/*
    KindlePDFViewer: a DC abstraction
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

#include "drawcontext.h"

static int newDrawContext(lua_State *L) {
	int rotate = luaL_optint(L, 1, 0);
	double zoom = luaL_optnumber(L, 2, (double) 1.0);
	int offset_x = luaL_optint(L, 3, 0);
	int offset_y = luaL_optint(L, 4, 0);
	double gamma = luaL_optnumber(L, 5, (double) -1.0);

	DrawContext *dc = (DrawContext*) lua_newuserdata(L, sizeof(DrawContext));
	dc->rotate = rotate;
	dc->zoom = zoom;
	dc->offset_x = offset_x;
	dc->offset_y = offset_y;
	dc->gamma = gamma;

	luaL_getmetatable(L, "drawcontext");
	lua_setmetatable(L, -2);

	return 1;
}

static int dcSetOffset(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	dc->offset_x = luaL_checkint(L, 2);
	dc->offset_y = luaL_checkint(L, 3);
	return 0;
}

static int dcGetOffset(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	lua_pushinteger(L, dc->offset_x);
	lua_pushinteger(L, dc->offset_y);
	return 2;
}

static int dcSetRotate(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	dc->rotate = luaL_checkint(L, 2);
	return 0;
}

static int dcSetZoom(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	dc->zoom = luaL_checknumber(L, 2);
	return 0;
}

static int dcGetRotate(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	lua_pushinteger(L, dc->rotate);
	return 1;
}

static int dcGetZoom(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	lua_pushnumber(L, dc->zoom);
	return 1;
}

static int dcSetGamma(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	dc->gamma = luaL_checknumber(L, 2);
	return 0;
}

static int dcGetGamma(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	lua_pushnumber(L, dc->gamma);
	return 1;
}

static const struct luaL_Reg drawcontext_meth[] = {
	{"setRotate", dcSetRotate},
	{"getRotate", dcGetRotate},
	{"setZoom", dcSetZoom},
	{"getZoom", dcGetZoom},
	{"setOffset", dcSetOffset},
	{"getOffset", dcGetOffset},
	{"setGamma", dcSetGamma},
	{"getGamma", dcGetGamma},
	{NULL, NULL}
};

static const struct luaL_Reg drawcontext_func[] = {
	{"new", newDrawContext},
	{NULL, NULL}
};

int luaopen_drawcontext(lua_State *L) {
	luaL_newmetatable(L, "drawcontext");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, drawcontext_meth);
	lua_pop(L, 1);
	luaL_register(L, "DrawContext", drawcontext_func);
	return 1;
}
