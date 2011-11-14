/*
    KindlePDFViewer: buffer for blitting muPDF data to framebuffer (blitbuffer)
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

#include "blitbuffer.h"

static int newBlitBuffer(lua_State *L) {
	int w = luaL_checkint(L, 1);
	int h = luaL_checkint(L, 2);
	BlitBuffer *bb = (BlitBuffer*) lua_newuserdata(L, sizeof(BlitBuffer) + (w * h * BLITBUFFER_BYTESPP) - 1);
	luaL_getmetatable(L, "blitbuffer");
	lua_setmetatable(L, -2);

	bb->w = w;
	bb->h = h;
	return 1;
}

static int freeBlitBuffer(lua_State *L) {
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 1, "blitbuffer");

	// lua will free the memory for the buffer itself
	return 0;
}

static const struct luaL_reg blitbuffer_func[] = {
	{"new", newBlitBuffer},
	{NULL, NULL}
};

static const struct luaL_reg blitbuffer_meth[] = {
	{"free", freeBlitBuffer},
	{NULL, NULL}
};

int luaopen_blitbuffer(lua_State *L) {
	luaL_newmetatable(L, "blitbuffer");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, blitbuffer_meth);
	luaL_register(L, "blitbuffer", blitbuffer_func);
	return 1;
}
