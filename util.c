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

static const struct luaL_reg util_func[] = {
	{"gettime", gettime},
	{NULL, NULL}
};

int luaopen_util(lua_State *L) {
	luaL_register(L, "util", util_func);
	return 1;
}
