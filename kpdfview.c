/*
    KindlePDFViewer
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
#include <fcntl.h>
#include <stdio.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "blitbuffer.h"
#include "pdf.h"
#include "einkfb.h"
#include "input.h"

lua_State *L;

int main(int argc, char **argv) {
	int i, err;

	if(argc < 2) {
		fprintf(stderr, "needs config file as first argument.\n");
		return -1;
	}

	/* set up Lua state */
	L = lua_open();
	if(L) {
		luaL_openlibs(L);

		luaopen_blitbuffer(L);
		luaopen_einkfb(L);
		luaopen_pdf(L);
		luaopen_input(L);
		luaopen_util(L);

		lua_newtable(L);
		for(i=2; i < argc; i++) {
			lua_pushstring(L, argv[i]);
			lua_rawseti(L, -2, i-1);
		}
		lua_setglobal(L, "ARGV");

		if(luaL_dofile(L, argv[1])) {
			fprintf(stderr, "lua config error: %s\n", lua_tostring(L, -1));
			lua_close(L);
			L=NULL;
			return -1;
		}
	}

	return 0;
}

