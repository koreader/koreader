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

#define DEBUG_CRENGINE 0

extern "C" {
#include "blitbuffer.h"
#include "drawcontext.h"
#include "cre.h"
}

#include "crengine.h"


typedef struct CreDocument {
	LVDocView *text_view;
	ldomDocument *dom_doc;
} CreDocument;

static int initCache(lua_State *L) {
	int cache_size = luaL_optint(L, 1, (2 << 20) * 64); // 64Mb on disk cache for DOM

	ldomDocCache::init(lString16("./cr3cache"), cache_size);

	return 0;
}

static int openDocument(lua_State *L) {
	const char *file_name = luaL_checkstring(L, 1);
	const char *style_sheet = luaL_checkstring(L, 2);

	int width = luaL_checkint(L, 3);
	int height = luaL_checkint(L, 4);
	lString8 css;

	CreDocument *doc = (CreDocument*) lua_newuserdata(L, sizeof(CreDocument));
	luaL_getmetatable(L, "credocument");
	lua_setmetatable(L, -2);

	doc->text_view = new LVDocView();
	//doc->text_view->setBackgroundColor(0xFFFFFF);
	//doc->text_view->setTextColor(0x000000);
	if (LVLoadStylesheetFile(lString16(style_sheet), css)){
		if (!css.empty()){
			doc->text_view->setStyleSheet(css);
		}
	}
	doc->text_view->setViewMode(DVM_SCROLL, -1);
	doc->text_view->Resize(width, height);
	doc->text_view->LoadDocument(file_name);
	doc->dom_doc = doc->text_view->getDocument();
	doc->text_view->Render();

	return 1;
}

static int getGammaIndex(lua_State *L) {
	lua_pushinteger(L, fontMan->GetGammaIndex());

	return 1;
}

static int setGammaIndex(lua_State *L) {
	int index = luaL_checkint(L, 1);

	fontMan->SetGammaIndex(index);

	return 0;
}

static int closeDocument(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	// should be save if called twice
	if(doc->text_view != NULL) {
		delete doc->text_view;
		doc->text_view = NULL;
	}

	return 0;
}

static int getNumberOfPages(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->getPageCount());

	return 1;
}

static int getCurrentPage(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->getCurPage()+1);

	return 1;
}

static int getPageFromXPointer(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	const char *xpointer_str = luaL_checkstring(L, 2);

	int page = 1;
	ldomXPointer xp = doc->dom_doc->createXPointer(lString16(xpointer_str));

	page = doc->text_view->getBookmarkPage(xp) + 1;
	lua_pushinteger(L, page);

	return 1;
}

static int getPosFromXPointer(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	const char *xpointer_str = luaL_checkstring(L, 2);

	int pos = 0;
	ldomXPointer xp = doc->dom_doc->createXPointer(lString16(xpointer_str));

	lvPoint pt = xp.toPoint();
	if (pt.y > 0) {
		pos = pt.y;
	}
	lua_pushinteger(L, pos);

	return 1;
}

static int getCurrentPos(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->GetPos());

	return 1;
}

static int getCurrentPercent(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_pushinteger(L, doc->text_view->getPosPercent());

	return 1;
}

static int getXPointer(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	ldomXPointer xp = doc->text_view->getBookmark();
	lua_pushstring(L, UnicodeToLocal(xp.toString()).c_str());

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
		lua_pushnumber(L, toc_tmp->getPage()+1); 
		lua_settable(L, -3);

		lua_pushstring(L, "xpointer");
		lua_pushstring(L, UnicodeToLocal(
							toc_tmp->getXPointer().toString()).c_str()
							);
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
 *    {
 *       page=12, 
 *       xpointer = "/body/DocFragment[11].0",
 *       depth=1, 
 *       title="chapter1"
 *    },
 *    {
 *       page=54, 
 *       xpointer = "/body/DocFragment[13].0",
 *       depth=1, 
 *       title="chapter2"
 *    },
 * }
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

/*
 * Return a table like this:
 * {
 *		"FreeMono",
 *		"FreeSans",
 *		"FreeSerif",
 * }
 *
 */
static int getFontFaces(lua_State *L) {
	int i = 0;
	lString16Collection face_list;

	fontMan->getFaceList(face_list);

	lua_newtable(L);
	for (i = 0; i < face_list.length(); i++)
	{
		lua_pushnumber(L, i+1);
		lua_pushstring(L, UnicodeToLocal(face_list[i]).c_str());
		lua_settable(L, -3);
	}

	return 1;
}

static int setFontFace(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	const char *face = luaL_checkstring(L, 2);

	doc->text_view->setDefaultFontFace(lString8(face));
	//fontMan->SetFallbackFontFace(lString8(face));

	return 0;
}

static int gotoPage(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int pageno = luaL_checkint(L, 2);

	doc->text_view->goToPage(pageno-1);

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

static int gotoXPointer(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	const char *xpointer_str = luaL_checkstring(L, 2);

	ldomXPointer xp = doc->dom_doc->createXPointer(lString16(xpointer_str));

	doc->text_view->goToBookmark(xp);

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

static int setFontSize(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int size = luaL_checkint(L, 2);

	doc->text_view->setFontSize(size);
	return 0;
}

static int setDefaultInterlineSpace(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	int space = luaL_checkint(L, 2);

	doc->text_view->setDefaultInterlineSpace(space);
	return 0;
}

static int setStyleSheet(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	const char* style_sheet_data = luaL_checkstring(L, 2);

	doc->text_view->setStyleSheet(lString8(style_sheet_data));
	return 0;
}

static int toggleFontBolder(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	doc->text_view->doCommand(DCMD_TOGGLE_BOLD);

	return 0;
}

static int cursorRight(lua_State *L) {
	//CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	//LVDocView *tv = doc->text_view;

	//ldomXPointer p = tv->getCurrentPageMiddleParagraph();
	//lString16 s = p.getText();
	//lString16 s = p.toString();
	//printf("~~~~~~~~~~%s\n", UnicodeToLocal(s).c_str());
		
	//tv->selectRange(*(tv->selectFirstPageLink()));
	//ldomXRange *r = tv->selectNextPageLink(true);
	//lString16 s = r->getRangeText();
	//printf("------%s\n", UnicodeToLocal(s).c_str());
	
	//tv->selectRange(*r);
	//tv->updateSelections();

	//LVPageWordSelector sel(doc->text_view);
	//doc->text_view->doCommand(DCMD_SELECT_FIRST_SENTENCE);
	//sel.moveBy(DIR_RIGHT, 2);
	//printf("---------------- %s\n", UnicodeToLocal(sel.getSelectedWord()->getText()).c_str());

	return 0;
}

static int getPageLinks(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	lua_newtable(L); // all links

	int pos = doc->text_view->GetPos();

	printf("## pos=%d\n", pos);

	ldomXRangeList links;
	ldomXRangeList & sel = doc->text_view->getDocument()->getSelections();
	doc->text_view->getCurrentPageLinks( links );
	int linkCount = links.length();
	if ( linkCount ) {
		sel.clear();
		for ( int i=0; i<linkCount; i++ ) {
			lString16 txt = links[i]->getRangeText();
			lString8 txt8 = UnicodeToLocal( txt );

			lString16 link = links[i]->getHRef();
			lString8 link8 = UnicodeToLocal( link );

			ldomXRange currSel;
			currSel = *links[i];

			lvPoint start_pt ( currSel.getStart().toPoint() );
			lvPoint end_pt ( currSel.getEnd().toPoint() );

			printf("# link %d start %d %d end %d %d '%s' %s\n", i,
				start_pt.x, start_pt.y, end_pt.x, end_pt.y,
				txt8.c_str(), link8.c_str()
			);

			lua_newtable(L); // new link

			lua_pushstring(L, "start_x");
			lua_pushinteger(L, start_pt.x);
			lua_settable(L, -3);
			lua_pushstring(L, "start_y");
			lua_pushinteger(L, start_pt.y);
			lua_settable(L, -3);
			lua_pushstring(L, "end_x");
			lua_pushinteger(L, end_pt.x);
			lua_settable(L, -3);
			lua_pushstring(L, "end_y");
			lua_pushinteger(L, end_pt.y);
			lua_settable(L, -3);

			const char * link_to = link8.c_str();

			if ( link_to[0] == '#' ) {
				lua_pushstring(L, "section");
				lua_pushstring(L, link_to);
				lua_settable(L, -3);

				sel.add( new ldomXRange(*links[i]) ); // highlight
			} else {
				lua_pushstring(L, "uri");
				lua_pushstring(L, link_to);
				lua_settable(L, -3);
			}

			lua_rawseti(L, -2, i + 1);

		}
		doc->text_view->updateSelections();
	}

	return 1;
}

static int gotoLink(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	const char *pos = luaL_checkstring(L, 2);

	doc->text_view->goLink(lString16(pos), true);

	return 0;
}

static int clearSelection(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");

	doc->text_view->clearSelection();

	return 0;
}

static int drawCurrentPage(lua_State *L) {
	CreDocument *doc = (CreDocument*) luaL_checkudata(L, 1, "credocument");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 3, "blitbuffer");

	int w = bb->w,
		h = bb->h;
	/* Set DrawBuf to 4bpp */
	LVGrayDrawBuf drawBuf(w, h, 4);

	doc->text_view->Resize(w, h);
	doc->text_view->Render();
	doc->text_view->Draw(drawBuf);
	
	uint8_t *bbptr = (uint8_t*)bb->data;
	uint8_t *pmptr = (uint8_t*)drawBuf.GetScanLine(0);
	int i,x;

	for (i = 0; i < h; i++) {
		for (x = 0; x < (bb->w / 2); x++) {
			/* When DrawBuf is set to 4bpp mode, CREngine still put every
			 * four bits in one byte, but left the last 4 bits zero*/
			bbptr[x] =  ~(pmptr[x*2] | (pmptr[x*2+1] >> 4));
		}
		if(bb->w & 1) {
			bbptr[x] = 255 - (pmptr[x*2] & 0xF0);
		}
		bbptr += bb->pitch;
		pmptr += w;
	}

	return 0;
}

static int registerFont(lua_State *L) {
	const char *fontfile = luaL_checkstring(L, 1);
	if ( !fontMan->RegisterFont(lString8(fontfile)) ) {
		return luaL_error(L, "cannot register font <%s>", fontfile);
	}
	return 0;
}

// ported from Android UI kpvcrlib/crengine/android/jni/docview.cpp

static int findText(lua_State *L) {
	CreDocument *doc		= (CreDocument*) luaL_checkudata(L, 1, "credocument");
	const char *l_pattern   = luaL_checkstring(L, 2);
	lString16 pattern		= lString16(l_pattern);
	int origin				= luaL_checkint(L, 3);
	bool reverse			= luaL_checkint(L, 4);
	bool caseInsensitive	= luaL_checkint(L, 5);

    if ( pattern.empty() )
        return 0;

    LVArray<ldomWord> words;
    lvRect rc;
    doc->text_view->GetPos( rc );
    int pageHeight = rc.height();
    int start = -1;
    int end = -1;
    if ( reverse ) {
        // reverse
        if ( origin == 0 ) {
            // from end current page to first page
            end = rc.bottom;
        } else if ( origin == -1 ) {
            // from last page to end of current page
            start = rc.bottom;
        } else { // origin == 1
            // from prev page to first page
            end = rc.top;
        }
    } else {
        // forward
        if ( origin == 0 ) {
            // from current page to last page
            start = rc.top;
        } else if ( origin == -1 ) {
            // from first page to current page
            end = rc.top;
        } else { // origin == 1
            // from next page to last
            start = rc.bottom;
        }
    }
    CRLog::debug("CRViewDialog::findText: Current page: %d .. %d", rc.top, rc.bottom);
    CRLog::debug("CRViewDialog::findText: searching for text '%s' from %d to %d origin %d", LCSTR(pattern), start, end, origin );
    if ( doc->text_view->getDocument()->findText( pattern, caseInsensitive, reverse, start, end, words, 200, pageHeight ) ) {
        CRLog::debug("CRViewDialog::findText: pattern found");
        doc->text_view->clearSelection();
        doc->text_view->selectWords( words );
        ldomMarkedRangeList * ranges = doc->text_view->getMarkedRanges();
        if ( ranges ) {
            if ( ranges->length()>0 ) {
                int pos = ranges->get(0)->start.y;
                //doc->text_view->SetPos(pos); // commented out not to mask lua code which does the same
        		CRLog::debug("# SetPos = %d", pos);
				lua_pushinteger(L, ranges->length()); // results found
				lua_pushinteger(L, pos);
				return 2;
            }
        }
        return 0;
    }
    CRLog::debug("CRViewDialog::findText: pattern not found");
    return 0;
}

static const struct luaL_Reg cre_func[] = {
	{"initCache", initCache},
	{"openDocument", openDocument},
	{"getFontFaces", getFontFaces},
	{"getGammaIndex", getGammaIndex},
	{"setGammaIndex", setGammaIndex},
	{"registerFont", registerFont},
	{NULL, NULL}
};

static const struct luaL_Reg credocument_meth[] = {
	/*--- get methods ---*/
	{"getPages", getNumberOfPages},
	{"getCurrentPage", getCurrentPage},
	{"getPageFromXPointer", getPageFromXPointer},
	{"getPosFromXPointer", getPosFromXPointer},
	{"getCurrentPos", getCurrentPos},
	{"getCurrentPercent", getCurrentPercent},
	{"getXPointer", getXPointer},
	{"getFullHeight", getFullHeight},
	{"getToc", getTableOfContent},
	/*--- set methods ---*/
	{"setFontFace", setFontFace},
	{"setFontSize", setFontSize},
	{"setDefaultInterlineSpace", setDefaultInterlineSpace},
	{"setStyleSheet", setStyleSheet},
	/* --- control methods ---*/
	{"gotoPage", gotoPage},
	{"gotoPercent", gotoPercent},
	{"gotoPos", gotoPos},
	{"gotoXPointer", gotoXPointer},
	{"zoomFont", zoomFont},
	{"toggleFontBolder", toggleFontBolder},
	//{"cursorLeft", cursorLeft},
	//{"cursorRight", cursorRight},
	{"drawCurrentPage", drawCurrentPage},
	{"findText", findText},
	{"getPageLinks", getPageLinks},
	{"gotoLink", gotoLink},
	{"clearSelection", clearSelection},
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


	/* initialize font manager for CREngine */
	InitFontManager(lString8());

#if DEBUG_CRENGINE
	CRLog::setStdoutLogger();
	CRLog::setLogLevel(CRLog::LL_DEBUG);
#endif

	return 1;
}
