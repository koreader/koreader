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
#include <unistd.h>
#include <stdlib.h>
#include <linux/input.h>
#include "input.h"
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>

#define OUTPUT_SIZE 21
#define CODE_IN_SAVER 10000
#define CODE_OUT_SAVER 10001

#define NUM_FDS 4
int inputfds[4] = { -1, -1, -1, -1 };
int slider_pid = -1;

int findFreeFdSlot() {
	int i;
	for(i=0; i<NUM_FDS; i++) {
		if(inputfds[i] == -1) {
			return i;
		}
	}
	return -1;
}

static int openInputDevice(lua_State *L) {
#ifndef EMULATE_READER
	int fd;
	const char* inputdevice = luaL_checkstring(L, 1);

	fd = findFreeFdSlot();
	if(fd == -1) {
		return luaL_error(L, "no free slot for new input device <%s>", inputdevice);
	}

	if(!strcmp("slider",inputdevice)) {
		/* special case: the power slider */
		int pipefd[2];
		int childpid;

		pipe(pipefd);
		if((childpid = fork()) == -1) {
			return luaL_error(L, "cannot fork() slider event listener");
		}
		if(childpid == 0) {
			FILE *fp;
			char std_out[OUTPUT_SIZE] = "";
			struct input_event ev;
			int ret;
			__u16 key_code = 10000;

			close(pipefd[0]);

			ev.type = EV_KEY;
			ev.code = key_code;
			ev.value = 1;

			/* listen power slider events */
			while(1) {
				fp = popen("exec lipc-wait-event com.lab126.powerd goingToScreenSaver,outOfScreenSaver", "r");
				if(fgets(std_out, OUTPUT_SIZE, fp) == NULL) {
					break;
				}
				pclose(fp);
				if(std_out[0] == 'g') {
					ev.code = CODE_IN_SAVER;
				} else if(std_out[0] == 'o') {
					ev.code = CODE_OUT_SAVER;
				} else {
					printf("Unrecognized event.\n");
				}
				/* fill event struct */
				gettimeofday(&ev.time, NULL);

				/* generate event */
				if(write(pipefd[1], &ev, sizeof(struct input_event)) == -1) {
					break;
				}
			}
			exit(0); /* cannot be reached?! */
		} else {
			close(pipefd[1]);
			inputfds[fd] = pipefd[0];
			slider_pid = childpid;
		}
	} else {
		inputfds[fd] = open(inputdevice, O_RDONLY | O_NONBLOCK, 0);
		if(inputfds[fd] != -1) {
			ioctl(inputfds[fd], EVIOCGRAB, 1);
			return 0;
		} else {
			return luaL_error(L, "error opening input device <%s>: %d", inputdevice, errno);
		}
	}
#else
	if(SDL_Init(SDL_INIT_VIDEO) < 0) {
		return luaL_error(L, "cannot initialize SDL.");
	}
	return 0;
#endif
}

static int closeInputDevices(lua_State *L) {
	int i;
	for(i=0; i<NUM_FDS; i++) {
		if(inputfds[i] != -1) {
			ioctl(inputfds[i], EVIOCGRAB, 0);
			close(i);
		}
	}
	if(slider_pid != -1) {
		/* kill and wait for child process */
		kill(slider_pid, SIGTERM);
		waitpid(-1, NULL, 0);
	}
	return 0;
}

static int waitForInput(lua_State *L) {
#ifndef EMULATE_READER
	fd_set fds;
	struct timeval timeout;
	int i, num, nfds;
	int usecs = luaL_optint(L, 1, -1); // we check for <0 later

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

	/* when no value is given as argument, we pass
	 * NULL to select() for the timeout value, setting no
	 * timeout at all.
	 */
	num = select(nfds, &fds, NULL, NULL, (usecs < 0) ? NULL : &timeout);
	if(num < 0) {
		return luaL_error(L, "Waiting for input failed: %d\n", errno);
	}

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
				return 1;
			}
		}
	}
	return 0;
#else
	SDL_Event event;
	while(SDL_WaitEvent(&event)) {
		switch(event.type) {
			case SDL_KEYDOWN:
				lua_newtable(L);
				lua_pushstring(L, "type");
				lua_pushinteger(L, EV_KEY);
				lua_settable(L, -3);
				lua_pushstring(L, "code");
				lua_pushinteger(L, event.key.keysym.scancode);
				lua_settable(L, -3);
				lua_pushstring(L, "value");
				lua_pushinteger(L, 1);
				lua_settable(L, -3);
				return 1;
			case SDL_KEYUP:
				lua_newtable(L);
				lua_pushstring(L, "type");
				lua_pushinteger(L, EV_KEY);
				lua_settable(L, -3);
				lua_pushstring(L, "code");
				lua_pushinteger(L, event.key.keysym.scancode);
				lua_settable(L, -3);
				lua_pushstring(L, "value");
				lua_pushinteger(L, 0);
				lua_settable(L, -3);
				return 1;
			case SDL_QUIT:
				return luaL_error(L, "application forced to quit");
		}
	}
	return luaL_error(L, "error waiting for SDL event.");
#endif
}

static const struct luaL_Reg input_func[] = {
	{"open", openInputDevice},
	{"closeAll", closeInputDevices},
	{"waitForEvent", waitForInput},
	{NULL, NULL}
};

int luaopen_input(lua_State *L) {
	luaL_register(L, "input", input_func);

	return 1;
}
