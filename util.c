/*
    KindlePDFViewer: miscellaneous utility functions for Lua
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

#include <sys/time.h>

#include "util.h"

static int gettime(lua_State *L) {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	lua_pushinteger(L, tv.tv_sec);
	lua_pushinteger(L, tv.tv_usec);
	return 2;
}

static int utf8charcode(lua_State *L) {
	size_t len;
	const char* utf8char = luaL_checklstring(L, 1, &len);
	int c;
	if(len == 1) {
		c = utf8char[0] & 0x7F; /* should not be needed */
	} else if(len == 2) {
		c = ((utf8char[0] & 0x1F) << 6) | (utf8char[1] & 0x3F);
	} else if(len == 3) {
		c = ((utf8char[0] & 0x0F) << 12) | ((utf8char[1] & 0x3F) << 6) | (utf8char[2] & 0x3F);
	} else {
		// 4, 5, 6 byte cases still missing
		return 0;
	}
	lua_pushinteger(L, c);
	return 1;
}

static const struct luaL_reg util_func[] = {
	{"gettime", gettime},
	{"utf8charcode", utf8charcode},
	{NULL, NULL}
};

int luaopen_util(lua_State *L) {
	luaL_register(L, "util", util_func);
	return 1;
}
