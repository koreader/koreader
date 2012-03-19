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
#ifndef _DRAWCONTEXT_H
#define _DRAWCONTEXT_H

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

typedef struct DrawContext {
	int rotate;
	double zoom;
	double gamma;
	int offset_x;
	int offset_y;
} DrawContext;

int luaopen_drawcontext(lua_State *L);
#endif

