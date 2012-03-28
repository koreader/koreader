/*
    KindlePDFViewer: CREngine abstraction for Lua
    Copyright (C) 2012 Hans-Werner Hilse <hilse@web.de>
                       Qingping Hou <qingping.hou@gmail.com>

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


extern "C" {
#include "blitbuffer.h"
#include "drawcontext.h"
#include "cre.h"
}

#include "crengine.h"

//using namespace std;

typedef struct CreDocument {
	LVDocView *text_view;
} CreDocument;


static int openDocument(lua_State *L) {
	const char *file_name = luaL_checkstring(L, 1);
	const char *style_sheet = luaL_checkstring(L, 2);
	int width = luaL_checkint(L, 3);
	int height = luaL_checkint(L, 4);

	CreDocument *doc = (CreDocument*) lua_newuserdata(L, sizeof(CreDocument));
	luaL_getmetatable(L, "credocument");
	lua_setmetatable(L, -2);

	doc->text_view = new LVDocView();
	doc->text_view->setStyleSheet(lString8(style_sheet));
	doc->text_view->LoadDocument(file_name);
	doc->text_view->setViewMode(DVM_SCROLL, -1);
	doc->text_view->Resize(width, height);
	doc->text_view->Render();

	return 1;
}

static int closeDocument(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	delete doc->text_view;

	return 0;
}

static int gotoPage(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int pageno = luaL_checkint(L, 2);

	doc->text_view->goToPage(pageno);

	return 0;
}

static int gotoPos(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int pos = luaL_checkint(L, 2);

	doc->text_view->SetPos(pos);

	return 0;
}

static int getNumberOfPages(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->getPageCount());

	return 1;
}

static int getCurrentPage(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->getCurPage());

	return 1;
}

static int getPos(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->GetPos());

	return 1;
}

static int getFullHeight(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->GetFullHeight());

	return 1;
}

static int drawCurrentPage(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 3, "blitbuffer");

	int w = bb->w,
		h = bb->h;
	LVGrayDrawBuf drawBuf(w, h, 8);

	doc->text_view->Resize(w, h);
	doc->text_view->Render();
	drawBuf.Clear(0xFFFFFF);
	doc->text_view->Draw(drawBuf);
	

	uint8_t *bbptr = (uint8_t*)bb->data;
	uint8_t *pmptr = (uint8_t*)drawBuf.GetScanLine(0);
	int i,x;

	for (i = 0; i < h; i++) {
		for (x = 0; x < (bb->w / 2); x++) {
			bbptr[x] = 255 - (((pmptr[x*2 + 1] & 0xF0) >> 4) | 
								(pmptr[x*2] & 0xF0));
		}
		if(bb->w & 1) {
			bbptr[x] = 255 - (pmptr[x*2] & 0xF0);
		}
		bbptr += bb->pitch;
		pmptr += w;
	}
}


static const struct luaL_Reg cre_func[] = {
	{"openDocument", openDocument},
	{NULL, NULL}
};

static const struct luaL_Reg credocument_meth[] = {
	{"getPages", getNumberOfPages},
	{"getCurrentPage", getCurrentPage},
	{"getPos", getPos},
	{"GetFullHeight", getFullHeight},
	{"gotoPos", gotoPos},
	{"gotoPage", gotoPage},
	{"drawCurrentPage", drawCurrentPage},
	//{"getTOC", getTableOfContent},
	{"close", closeDocument},
	{"__gc", closeDocument},
	{NULL, NULL}
};

int luaopen_cre(lua_State *L) {
	luaL_newmetatable(L, "credocument");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, credocument_meth);
	lua_pop(L, 1);
	luaL_register(L, "cre", cre_func);


	/* initialize fonts for CREngine */
	InitFontManager(lString8("./fonts"));

    lString8 fontDir("./fonts");
	LVContainerRef dir = LVOpenDirectory( LocalToUnicode(fontDir).c_str() );
	if ( !dir.isNull() )
	for ( int i=0; i<dir->GetObjectCount(); i++ ) {
		const LVContainerItemInfo * item = dir->GetObjectInfo(i);
		lString16 fileName = item->GetName();
		if ( !item->IsContainer() && fileName.length()>4 && lString16(fileName, fileName.length()-4, 4)==L".ttf" ) {
			lString8 fn = UnicodeToLocal(fileName);
			printf("loading font: %s\n", fn.c_str());
			if ( !fontMan->RegisterFont(fn) ) {
				printf("    failed\n");
			}
		}
	}

#ifdef DEBUG_CRENGINE
	CRLog::setStdoutLogger();
	CRLog::setLogLevel(CRLog::LL_DEBUG);
#endif

	return 1;
}
