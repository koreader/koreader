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
#ifndef _BLITBUFFER_H
#define _BLITBUFFER_H

#include <stdint.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

typedef struct BlitBuffer {
	int w;
	int h;
	int pitch;
	uint8_t *data;
	uint8_t allocated;
} BlitBuffer;

int newBlitBufferNative(lua_State *L, int w, int h, int pitch, BlitBuffer **newBuffer);
int luaopen_blitbuffer(lua_State *L);

#endif
