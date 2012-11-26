/*
    KindlePDFViewer: a KOPTContext abstraction
    Copyright (C) 2012 Huang Xin <chrox.huang@gmail.com>

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
#ifndef _KOPTCONTEXT_H
#define _KOPTCONTEXT_H

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include "koptreflow.h"

int luaopen_koptcontext(lua_State *L);
#endif
