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
#include <sys/statvfs.h>
#include <unistd.h>

#include "util.h"

static int gettime(lua_State *L) {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	lua_pushinteger(L, tv.tv_sec);
	lua_pushinteger(L, tv.tv_usec);
	return 2;
}

static int util_sleep(lua_State *L) {
	unsigned int seconds = luaL_optint(L, 1, 0);
	sleep(seconds);
	return 0;
}

static int util_usleep(lua_State *L) {
	useconds_t useconds = luaL_optint(L, 1, 0);
	usleep(useconds);
	return 0;
}

static int util_df(lua_State *L) {
	const char *path = luaL_checkstring(L, 1);
	struct statvfs vfs;
	statvfs(path, &vfs);
	lua_pushnumber(L, (double)vfs.f_bfree * (double)vfs.f_bsize);
	return 1;
}

/* Turn UTF-8 char code to Unicode */
static int utf8charcode(lua_State *L) {
	size_t len;
	const char *utf8char = luaL_checklstring(L, 1, &len);
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

static int isEmulated(lua_State *L) {
#ifdef EMULATE_READER
	lua_pushinteger(L, 1);
#else
	lua_pushinteger(L, 0);
#endif
	return 1;
}

static const struct luaL_Reg util_func[] = {
	{"gettime", gettime},
	{"sleep", util_sleep},
	{"usleep", util_usleep},
	{"utf8charcode", utf8charcode},
	{"isEmulated", isEmulated},
	{"df", util_df},
	{NULL, NULL}
};

int luaopen_util(lua_State *L) {
	luaL_register(L, "util", util_func);
	return 1;
}
