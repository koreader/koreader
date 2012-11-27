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

#include "koptcontext.h"

static int newKOPTContext(lua_State *L) {
	int trim = 1;
	int wrap = 1;
	int indent = 1;
	int rotate = 0;
	int columns = 2;
	int offset_x = 0;
	int offset_y = 0;
	int dev_dpi = 167;
	int dev_width = 600;
	int dev_height = 800;
	int page_width = 600;
	int page_height = 800;
	int straighten = 0;
	int justification = -1;
	int read_max_width = 3000;
	int read_max_height = 4000;

	double zoom = 1.0;
	double margin = 0.06;
	double quality = 1.0;
	double contrast = 1.0;
	double defect_size = 1.0;
	double line_spacing = 1.2;
	double word_spacing = 1.375;
	double shrink_factor = 0.9;

	uint8_t *data = NULL;
	BBox bbox = {0, 0, 0, 0};
	WILLUSBITMAP *src;
	int precache = 0;

	KOPTContext *kc = (KOPTContext*) lua_newuserdata(L, sizeof(KOPTContext));

	kc->trim = trim;
	kc->wrap = wrap;
	kc->indent = indent;
	kc->rotate = rotate;
	kc->columns = columns;
	kc->offset_x = offset_x;
	kc->offset_y = offset_y;
	kc->dev_dpi = dev_dpi;
	kc->dev_width = dev_width;
	kc->dev_height = dev_height;
	kc->page_width = page_width;
	kc->page_height = page_height;
	kc->straighten = straighten;
	kc->justification = justification;
	kc->read_max_width = read_max_width;
	kc->read_max_height = read_max_height;

	kc->zoom = zoom;
	kc->margin = margin;
	kc->quality = quality;
	kc->contrast = contrast;
	kc->defect_size = defect_size;
	kc->line_spacing = line_spacing;
	kc->word_spacing = word_spacing;
	kc->shrink_factor = shrink_factor;

	kc->data = data;
	kc->bbox = bbox;
	kc->src = src;
	kc->precache = precache;

	luaL_getmetatable(L, "koptcontext");
	lua_setmetatable(L, -2);

	return 1;
}

static int kcSetBBox(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->bbox.x0 = luaL_checknumber(L, 2);
	kc->bbox.y0 = luaL_checknumber(L, 3);
	kc->bbox.x1 = luaL_checknumber(L, 4);
	kc->bbox.y1 = luaL_checknumber(L, 5);
	return 0;
}

static int kcSetTrim(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->trim = luaL_checkint(L, 2);
	return 0;
}

static int kcGetTrim(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	lua_pushinteger(L, kc->trim);
	return 1;
}

static int kcSetWrap(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->wrap = luaL_checkint(L, 2);
	return 0;
}

static int kcSetIndent(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->indent = luaL_checkint(L, 2);
	return 0;
}

static int kcSetRotate(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->rotate = luaL_checkint(L, 2);
	return 0;
}

static int kcSetColumns(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->columns = luaL_checkint(L, 2);
	return 0;
}

static int kcSetOffset(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->offset_x = luaL_checkint(L, 2);
	kc->offset_y = luaL_checkint(L, 3);
	return 0;
}

static int kcGetOffset(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	lua_pushinteger(L, kc->offset_x);
	lua_pushinteger(L, kc->offset_y);
	return 2;
}

static int kcSetDeviceDPI(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->dev_dpi = luaL_checkint(L, 2);
	return 0;
}

static int kcSetDeviceDim(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->dev_width = luaL_checkint(L, 2);
	kc->dev_height = luaL_checkint(L, 3);
	return 0;
}

static int kcGetPageDim(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	lua_pushinteger(L, kc->page_width);
	lua_pushinteger(L, kc->page_height);
	return 2;
}

static int kcSetStraighten(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->straighten = luaL_checkint(L, 2);
	return 0;
}

static int kcSetJustification(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->justification = luaL_checkint(L, 2);
	return 0;
}

static int kcSetZoom(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->zoom = luaL_checknumber(L, 2);
	return 0;
}

static int kcGetZoom(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	lua_pushnumber(L, kc->zoom);
	return 1;
}

static int kcSetMargin(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->margin = luaL_checknumber(L, 2);
	return 0;
}

static int kcSetQuality(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->quality = luaL_checknumber(L, 2);
	return 0;
}

static int kcSetContrast(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->contrast = luaL_checknumber(L, 2);
	return 0;
}

static int kcSetDefectSize(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->defect_size = luaL_checknumber(L, 2);
	return 0;
}

static int kcSetLineSpacing(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->line_spacing = luaL_checknumber(L, 2);
	return 0;
}

static int kcSetWordSpacing(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->word_spacing = luaL_checknumber(L, 2);
	return 0;
}

static int kcSetPreCache(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	kc->precache = 1;
	return 0;
}

static int kcIsPreCache(lua_State *L) {
	KOPTContext *kc = (KOPTContext*) luaL_checkudata(L, 1, "koptcontext");
	lua_pushinteger(L, kc->precache);
	return 1;
}

static const struct luaL_Reg koptcontext_meth[] = {
	{"setBBox", kcSetBBox},
	{"setTrim", kcSetTrim},
	{"getTrim", kcGetTrim},
	{"setWrap", kcSetWrap},
	{"setIndent", kcSetIndent},
	{"setRotate", kcSetRotate},
	{"setColumns", kcSetColumns},
	{"setOffset", kcSetOffset},
	{"getOffset", kcGetOffset},
	{"setDeviceDim", kcSetDeviceDim},
	{"setDeviceDPI", kcSetDeviceDPI},
	{"getPageDim", kcGetPageDim},
	{"setStraighten", kcSetStraighten},
	{"setJustification", kcSetJustification},

	{"setZoom", kcSetZoom},
	{"getZoom", kcGetZoom},
	{"setMargin", kcSetMargin},
	{"setQuality", kcSetQuality},
	{"setContrast", kcSetContrast},
	{"setDefectSize", kcSetDefectSize},
	{"setLineSpacing", kcSetLineSpacing},
	{"setWordSpacing", kcSetWordSpacing},

	{"setPreCache", kcSetPreCache},
	{"isPreCache", kcIsPreCache},
	{NULL, NULL}
};

static const struct luaL_Reg koptcontext_func[] = {
	{"new", newKOPTContext},
	{NULL, NULL}
};

int luaopen_koptcontext(lua_State *L) {
	luaL_newmetatable(L, "koptcontext");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, koptcontext_meth);
	lua_pop(L, 1);
	luaL_register(L, "KOPTContext", koptcontext_func);
	return 1;
}
