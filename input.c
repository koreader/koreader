/*
    KindlePDFViewer: input abstraction for Lua
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
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <linux/input.h>
#include "input.h"

#define NUM_FDS 3
int inputfds[3] = { -1, -1, -1 };

static int openInputDevice(lua_State *L) {
	int i;
	const char* inputdevice = luaL_checkstring(L, 1);

	for(i=0; i<NUM_FDS; i++) {
		if(inputfds[i] == -1) {
			inputfds[i] = open(inputdevice, O_RDONLY | O_NONBLOCK, 0);
			if(inputfds[i] != -1) {
#ifndef EMULATE_EINKFB
				ioctl(inputfds[i], EVIOCGRAB, 1);
#endif
				return 0;
			} else {
				luaL_error(L, "error opening input device <%s>: %d", inputdevice, errno);
			}
		}
	}
	return luaL_error(L, "no free slot for new input device <%s>", inputdevice);
}

static int closeInputDevices(lua_State *L) {
	int i;
	for(i=0; i<NUM_FDS; i++) {
		if(inputfds[i] != -1) {
			ioctl(inputfds[i], EVIOCGRAB, 0);
			close(i);
		}
	}
	return 0;
}

static int waitForInput(lua_State *L) {
	fd_set fds;
	struct timeval timeout;
	int i, j, num, nfds;
	int usecs = luaL_optint(L, 1, 0x7FFFFFFF);

	timeout.tv_sec = (usecs/1000000);
	timeout.tv_usec = (usecs%1000000);

	nfds = 0;

	FD_ZERO(&fds);
	for(i=0; i<NUM_FDS; i++) {
		if(inputfds[i] != -1)
			FD_SET(inputfds[i], &fds);
		if(inputfds[i] + 1 > nfds)
			nfds = inputfds[i] + 1;
	}

	num = select(nfds, &fds, NULL, NULL, &timeout);
	if(num < 0) {
		return luaL_error(L, "Waiting for input failed: %d\n", errno);
	}

	lua_newtable(L);
	j=1;

	for(i=0; i<NUM_FDS; i++) {
		if(inputfds[i] != -1 && FD_ISSET(inputfds[i], &fds)) {
			struct input_event input;
			int n;

			n = read(inputfds[i], &input, sizeof(struct input_event));
			if(n == sizeof(struct input_event)) {
				lua_newtable(L);
				lua_pushstring(L, "type");
				lua_pushinteger(L, (int) input.type);
				lua_settable(L, -3);
				lua_pushstring(L, "code");
				lua_pushinteger(L, (int) input.code);
				lua_settable(L, -3);
				lua_pushstring(L, "value");
				lua_pushinteger(L, (int) input.value);
				lua_settable(L, -3);
				lua_rawseti(L, -2, j);
				j++;
			}
		}
	}

	return 1;
}

static const struct luaL_reg input_func[] = {
	{"open", openInputDevice},
	{"closeAll", closeInputDevices},
	{"waitForEvent", waitForInput},
	{NULL, NULL}
};

int luaopen_input(lua_State *L) {
	luaL_register(L, "input", input_func);

	return 1;
}
