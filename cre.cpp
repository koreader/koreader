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
	doc->text_view->setBackgroundColor(0x000000);
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

static int getPosPercent(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->getPosPercent());

	return 1;
}

static int getFullHeight(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->GetFullHeight());

	return 1;
}

/*
 * helper function for getTableOfContent()
 */
static int walkTableOfContent(lua_State *L, LVTocItem *toc, int *count) {
	LVTocItem *toc_tmp = NULL;
	int i = 0,
		nr_child = toc->getChildCount();

	for(i = 0; i < nr_child; i++)  {
		toc_tmp = toc->getChild(i);
		lua_pushnumber(L, (*count)++);

		/* set subtable, Toc entry */
		lua_newtable(L);
		lua_pushstring(L, "page");
		lua_pushnumber(L, toc_tmp->getY());
		lua_settable(L, -3);

		lua_pushstring(L, "depth");
		lua_pushnumber(L, toc_tmp->getLevel()); 
		lua_settable(L, -3);

		lua_pushstring(L, "title");
		lua_pushstring(L, UnicodeToLocal(toc_tmp->getName()).c_str());
		lua_settable(L, -3);


		/* set Toc entry to Toc table */
		lua_settable(L, -3);

		if (toc_tmp->getChildCount() > 0) {
			walkTableOfContent(L, toc_tmp, count);
		}
	}
	return 0;
}

/*
 * Return a table like this:
 * {
 *		{page=12, depth=1, title="chapter1"},
 *		{page=54, depth=1, title="chapter2"},
 * }
 *
 * Warnning: not like pdf or djvu support, page here refers to the
 * position(height) within the document, not the real page number.
 *
 */
static int getTableOfContent(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	
	LVTocItem * toc = doc->text_view->getToc();
	int count = 0;

	lua_newtable(L);
	walkTableOfContent(L, toc, &count);

	return 1;
}

static int gotoPage(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int pageno = luaL_checkint(L, 2);

	doc->text_view->goToPage(pageno);

	return 0;
}

static int gotoPercent(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int percent = luaL_checkint(L, 2);

	doc->text_view->SetPos(percent * doc->text_view->GetFullHeight() / 10000);

	return 0;
}

static int gotoPos(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int pos = luaL_checkint(L, 2);

	doc->text_view->SetPos(pos);

	return 0;
}

/* zoom font by given delta and return zoomed font size */
static int zoomFont(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int delta = luaL_checkint(L, 2);

	doc->text_view->ZoomFont(delta);

	lua_pushnumber(L, doc->text_view->getFontSize());
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
	{"getPosPercent", getPosPercent},
	{"getFullHeight", getFullHeight},
	{"getToc", getTableOfContent},
	{"gotoPage", gotoPage},
	{"gotoPercent", gotoPercent},
	{"gotoPos", gotoPos},
	{"zoomFont", zoomFont},
	{"drawCurrentPage", drawCurrentPage},
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
