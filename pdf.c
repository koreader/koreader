/*
    KindlePDFViewer: MuPDF abstraction for Lua
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
#include <fitz/fitz.h>
#include <pdf/mupdf.h>

#include "blitbuffer.h"
#include "pdf.h"

typedef struct PdfDocument {
	pdf_document *xref;
	fz_context *context;
	int pages;
} PdfDocument;

typedef struct PdfPage {
	int num;
#ifdef USE_DISPLAY_LIST
	fz_display_list *list;
#endif
	pdf_page *page;
	PdfDocument *doc;
} PdfPage;

typedef struct DrawContext {
	int rotate;
	double zoom;
	double gamma;
	int offset_x;
	int offset_y;
} DrawContext;

static int openDocument(lua_State *L) {
	const char *filename = luaL_checkstring(L, 1);
	const char *password = luaL_checkstring(L, 2);
	PdfDocument *doc = (PdfDocument*) lua_newuserdata(L, sizeof(PdfDocument));

	luaL_getmetatable(L, "pdfdocument");
	lua_setmetatable(L, -2);

	doc->context = fz_new_context(NULL, NULL, 64 << 20); // 64MB limit

	fz_try(doc->context) {
		doc->xref = pdf_open_document(doc->context, filename);
	}
	fz_catch(doc->context) {
		return luaL_error(L, "cannot open PDF file <%s>", filename);
	}

	if(pdf_needs_password(doc->xref)) {
		if (!pdf_authenticate_password(doc->xref, password))
			return luaL_error(L, "cannot authenticate");
	}
	doc->pages = pdf_count_pages(doc->xref);
	return 1;
}

static int closeDocument(lua_State *L) {
	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");
	if(doc->xref != NULL) {
		pdf_close_document(doc->xref);
		doc->xref = NULL;
	}
	if(doc->context != NULL) {
		fz_free_context(doc->context);
		doc->context = NULL;
	}
}

static int getNumberOfPages(lua_State *L) {
	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");
	lua_pushinteger(L, doc->pages);
	return 1;
}

/*
 * Return a table with (title,page) pair as entry:
 * {"chapter1"=12, "chapter2"=20}
 */
static int getTableOfContent(lua_State *L) {
	fz_outline *ol;
	int i;

	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");
	ol = pdf_load_outline(doc->xref);

	lua_newtable(L);
	i = 1;
	while(ol) {
		lua_pushnumber(L, i);

		/* set subtable */
		lua_newtable(L);
		lua_pushstring(L, "page");
		lua_pushnumber(L, ol->dest.ld.gotor.page + 1);
		lua_settable(L, -3);
		lua_pushstring(L, "level");
		lua_pushnumber(L, 1); // level 1
		lua_settable(L, -3);
		lua_pushstring(L, "title");
		lua_pushstring(L, ol->title);
		lua_settable(L, -3);

		lua_settable(L, -3);

		i++;
		ol = ol->next;
	}
	return 1;
}

static int newDrawContext(lua_State *L) {
	int rotate = luaL_optint(L, 1, 0);
	double zoom = luaL_optnumber(L, 2, (double) 1.0);
	int offset_x = luaL_optint(L, 3, 0);
	int offset_y = luaL_optint(L, 4, 0);
	double gamma = luaL_optnumber(L, 5, (double) -1.0);

	DrawContext *dc = (DrawContext*) lua_newuserdata(L, sizeof(DrawContext));
	dc->rotate = rotate;
	dc->zoom = zoom;
	dc->offset_x = offset_x;
	dc->offset_y = offset_y;
	dc->gamma = gamma;

	luaL_getmetatable(L, "drawcontext");
	lua_setmetatable(L, -2);

	return 1;
}

static int dcSetOffset(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	dc->offset_x = luaL_checkint(L, 2);
	dc->offset_y = luaL_checkint(L, 3);
	return 0;
}

static int dcGetOffset(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	lua_pushinteger(L, dc->offset_x);
	lua_pushinteger(L, dc->offset_y);
	return 2;
}

static int dcSetRotate(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	dc->rotate = luaL_checkint(L, 2);
	return 0;
}

static int dcSetZoom(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	dc->zoom = luaL_checknumber(L, 2);
	return 0;
}

static int dcGetRotate(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	lua_pushinteger(L, dc->rotate);
	return 1;
}

static int dcGetZoom(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	lua_pushnumber(L, dc->zoom);
	return 1;
}

static int dcSetGamma(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	dc->gamma = luaL_checknumber(L, 2);
	return 0;
}

static int dcGetGamma(lua_State *L) {
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 1, "drawcontext");
	lua_pushnumber(L, dc->gamma);
	return 1;
}

static int openPage(lua_State *L) {
	fz_device *dev;

	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");

	int pageno = luaL_checkint(L, 2);

	if(pageno < 1 || pageno > doc->pages) {
		return luaL_error(L, "cannot open page #%d, out of range (1-%d)", pageno, doc->pages);
	}

	PdfPage *page = (PdfPage*) lua_newuserdata(L, sizeof(PdfPage));

	luaL_getmetatable(L, "pdfpage");
	lua_setmetatable(L, -2);

	fz_try(doc->context) {
		page->page = pdf_load_page(doc->xref, pageno - 1);
	}
	fz_catch(doc->context) {
		return luaL_error(L, "cannot open page #%d", pageno);
	}

	page->doc = doc;

	return 1;
}

static int getPageSize(lua_State *L) {
	fz_matrix ctm;
	fz_rect bbox;
	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");

	ctm = fz_translate(0, -page->page->mediabox.y1);
	ctm = fz_concat(ctm, fz_scale(dc->zoom, -dc->zoom));
	ctm = fz_concat(ctm, fz_rotate(page->page->rotate));
	ctm = fz_concat(ctm, fz_rotate(dc->rotate));
	bbox = fz_transform_rect(ctm, page->page->mediabox);
	
       	lua_pushnumber(L, bbox.x1-bbox.x0);
	lua_pushnumber(L, bbox.y1-bbox.y0);

	return 2;
}

static int getUsedBBox(lua_State *L) {
	fz_bbox result;
	fz_matrix ctm;
	fz_device *dev;
	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");

	/* returned BBox is in centi-point (n * 0.01 pt) */
	ctm = fz_scale(100, 100);
	ctm = fz_concat(ctm, fz_rotate(page->page->rotate));

	fz_try(page->doc->context) {
		dev = fz_new_bbox_device(page->doc->context, &result);
		pdf_run_page(page->doc->xref, page->page, dev, ctm, NULL);
	}
	fz_always(page->doc->context) {
		fz_free_device(dev);
	}
	fz_catch(page->doc->context) {
		return luaL_error(L, "cannot calculate bbox for page");
	}

       	lua_pushnumber(L, ((double)result.x0)/100);
	lua_pushnumber(L, ((double)result.y0)/100);
       	lua_pushnumber(L, ((double)result.x1)/100);
	lua_pushnumber(L, ((double)result.y1)/100);

	return 4;
}

static int closePage(lua_State *L) {
	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");
	if(page->page != NULL) {
		pdf_free_page(page->doc->xref, page->page);
		page->page = NULL;
	}
	return 0;
}

static int drawPage(lua_State *L) {
	fz_pixmap *pix;
	fz_device *dev;
	fz_matrix ctm;
	fz_bbox bbox;
	fz_bbox rect;

	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 3, "blitbuffer");
	rect.x0 = luaL_checkint(L, 4);
	rect.y0 = luaL_checkint(L, 5);
	rect.x1 = rect.x0 + bb->w;
	rect.y1 = rect.y0 + bb->h;
	pix = fz_new_pixmap_with_rect(page->doc->context, fz_device_gray, rect);
	fz_clear_pixmap_with_value(page->doc->context, pix, 0xff);

	ctm = fz_scale(dc->zoom, dc->zoom);
	ctm = fz_concat(ctm, fz_rotate(page->page->rotate));
	ctm = fz_concat(ctm, fz_rotate(dc->rotate));
	ctm = fz_concat(ctm, fz_translate(dc->offset_x, dc->offset_y));
	dev = fz_new_draw_device(page->doc->context, pix);
#ifdef MUPDF_TRACE
	fz_device *tdev;
	fz_try(page->doc->context) {
		tdev = fz_new_trace_device(page->doc->context);
		pdf_run_page(page->doc->xref, page->page, tdev, ctm, NULL);
	}
	fz_always(page->doc->context) {
		fz_free_device(tdev);
	}
#endif
	pdf_run_page(page->doc->xref, page->page, dev, ctm, NULL);
	fz_free_device(dev);

	if(dc->gamma >= 0.0) {
		fz_gamma_pixmap(page->doc->context, pix, dc->gamma);
	}

	uint8_t *bbptr = (uint8_t*)bb->data;
	uint16_t *pmptr = (uint16_t*)pix->samples;
	int x, y;

	for(y = 0; y < bb->h; y++) {
		for(x = 0; x < (bb->w / 2); x++) {
			bbptr[x] = (((pmptr[x*2 + 1] & 0xF0) >> 4) | (pmptr[x*2] & 0xF0)) ^ 0xFF;
		}
		if(bb->w & 1) {
			bbptr[x] = pmptr[x*2] & 0xF0;
		}
		bbptr += bb->pitch;
		pmptr += bb->w;
	}

	fz_drop_pixmap(page->doc->context, pix);

	return 0;
}

static const struct luaL_reg pdf_func[] = {
	{"openDocument", openDocument},
	{"newDC", newDrawContext},
	{NULL, NULL}
};

static const struct luaL_reg pdfdocument_meth[] = {
	{"openPage", openPage},
	{"getPages", getNumberOfPages},
	{"getTOC", getTableOfContent},
	{"close", closeDocument},
	{"__gc", closeDocument},
	{NULL, NULL}
};

static const struct luaL_reg pdfpage_meth[] = {
	{"getSize", getPageSize},
	{"getUsedBBox", getUsedBBox},
	{"close", closePage},
	{"__gc", closePage},
	{"draw", drawPage},
	{NULL, NULL}
};

static const struct luaL_reg drawcontext_meth[] = {
	{"setRotate", dcSetRotate},
	{"getRotate", dcGetRotate},
	{"setZoom", dcSetZoom},
	{"getZoom", dcGetZoom},
	{"setOffset", dcSetOffset},
	{"getOffset", dcGetOffset},
	{"setGamma", dcSetGamma},
	{"getGamma", dcGetGamma},
	{NULL, NULL}
};

int luaopen_pdf(lua_State *L) {
	luaL_newmetatable(L, "pdfdocument");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, pdfdocument_meth);
	lua_pop(L, 1);
	luaL_newmetatable(L, "pdfpage");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, pdfpage_meth);
	lua_pop(L, 1);
	luaL_newmetatable(L, "drawcontext");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, drawcontext_meth);
	lua_pop(L, 1);
	luaL_register(L, "pdf", pdf_func);
	return 1;
}
