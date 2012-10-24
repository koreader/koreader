/*
    KindlePDFViewer: DjvuLibre abstraction for Lua
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
#include <math.h>
#include <string.h>
#include <errno.h>
#include <libdjvu/miniexp.h>
#include <libdjvu/ddjvuapi.h>

#include "blitbuffer.h"
#include "drawcontext.h"
#include "djvu.h"

#define MIN(a, b)      ((a) < (b) ? (a) : (b))
#define MAX(a, b)      ((a) > (b) ? (a) : (b))

typedef struct DjvuDocument {
	ddjvu_context_t *context;
	ddjvu_document_t *doc_ref;
	ddjvu_format_t *pixelformat;
} DjvuDocument;

typedef struct DjvuPage {
	int num;
	ddjvu_page_t *page_ref;
	ddjvu_pageinfo_t info;
	DjvuDocument *doc;
} DjvuPage;

static int handle(lua_State *L, ddjvu_context_t *ctx, int wait)
{
	const ddjvu_message_t *msg;
	if (!ctx)
		return -1;
	if (wait)
		msg = ddjvu_message_wait(ctx);
	while ((msg = ddjvu_message_peek(ctx)))
	{
	  switch(msg->m_any.tag)
		{
		case DDJVU_ERROR:
			if (msg->m_error.filename) {
				return luaL_error(L, "ddjvu: %s\nddjvu: '%s:%d'\n",
					msg->m_error.message, msg->m_error.filename,
					msg->m_error.lineno);
			} else {
				return luaL_error(L, "ddjvu: %s\n", msg->m_error.message);
			}
		default:
		  break;
		}
	  ddjvu_message_pop(ctx);
	}

	return 0;
}

static int openDocument(lua_State *L) {
	const char *filename = luaL_checkstring(L, 1);
	int cache_size = luaL_optint(L, 2, 10 << 20);

	DjvuDocument *doc = (DjvuDocument*) lua_newuserdata(L, sizeof(DjvuDocument));
	luaL_getmetatable(L, "djvudocument");
	lua_setmetatable(L, -2);

	doc->context = ddjvu_context_create("kindlepdfviewer");
	if (! doc->context) {
		return luaL_error(L, "cannot create context");
	}

	//printf("## cache_size = %d\n", cache_size);
	ddjvu_cache_set_size(doc->context, (unsigned long)cache_size);

	doc->doc_ref = ddjvu_document_create_by_filename_utf8(doc->context, filename, TRUE);
	if (! doc->doc_ref)
		return luaL_error(L, "cannot open DjVu file <%s>", filename);
	while (! ddjvu_document_decoding_done(doc->doc_ref))
		handle(L, doc->context, True);

	doc->pixelformat = ddjvu_format_create(DDJVU_FORMAT_GREY8, 0, NULL);
	if (! doc->pixelformat) {
		return luaL_error(L, "cannot create DjVu pixelformat for <%s>", filename);
	}
	ddjvu_format_set_row_order(doc->pixelformat, 1);
	ddjvu_format_set_y_direction(doc->pixelformat, 1);
	/* dithering bits <8 are ignored by djvulibre */
	/* ddjvu_format_set_ditherbits(doc->pixelformat, 4); */

	return 1;
}

static int closeDocument(lua_State *L) {
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");

	// should be safe if called twice
	if (doc->doc_ref != NULL) {
		ddjvu_document_release(doc->doc_ref);
		doc->doc_ref = NULL;
	}
	if (doc->context != NULL) {
		ddjvu_context_release(doc->context);
		doc->context = NULL;
	}
	if (doc->pixelformat != NULL) {
		ddjvu_format_release(doc->pixelformat);
		doc->pixelformat = NULL;
	}
	return 0;
}

static int getNumberOfPages(lua_State *L) {
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");
	lua_pushinteger(L, ddjvu_document_get_pagenum(doc->doc_ref));
	return 1;
}

static int walkTableOfContent(lua_State *L, miniexp_t r, int *count, int depth) {
	depth++;

	miniexp_t lista = miniexp_cdr(r); // go inside bookmars in the list

	int length = miniexp_length(r);
	int counter = 0;
	const char* page_name;
	int page_number;

	while(counter < length-1) {
		lua_pushnumber(L, *count);
		lua_newtable(L);

		lua_pushstring(L, "page");
		page_name = miniexp_to_str(miniexp_car(miniexp_cdr(miniexp_nth(counter, lista))));
		if(page_name != NULL && page_name[0] == '#') {
			errno = 0;
			page_number = strtol(page_name + 1, NULL, 10);
			if(!errno) {
				lua_pushnumber(L, page_number);
			} else {
				/* we can not parse this as a number, TODO: parse page names */
				lua_pushnumber(L, -1);
			}
		} else {
			/* something we did not expect here */
			lua_pushnumber(L, -1);
		}
		lua_settable(L, -3);

		lua_pushstring(L, "depth");
		lua_pushnumber(L, depth);
		lua_settable(L, -3);

		lua_pushstring(L, "title");
		lua_pushstring(L, miniexp_to_str(miniexp_car(miniexp_nth(counter, lista))));
		lua_settable(L, -3);

		lua_settable(L, -3);

		(*count)++;

		if (miniexp_length(miniexp_cdr(miniexp_nth(counter, lista))) > 1) {
			walkTableOfContent(L, miniexp_cdr(miniexp_nth(counter, lista)), count, depth);
		}
		counter++;
	}
	return 0;
}

static int getTableOfContent(lua_State *L) {
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");
	miniexp_t r;
	int count = 1;

	while ((r=ddjvu_document_get_outline(doc->doc_ref))==miniexp_dummy)
		handle(L, doc->context, True);

	//printf("lista: %s\n", miniexp_to_str(miniexp_car(miniexp_nth(1, miniexp_cdr(r)))));

	lua_newtable(L);
	walkTableOfContent(L, r, &count, 0);

	return 1;
}

static int openPage(lua_State *L) {
	ddjvu_status_t r;
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");
	int pageno = luaL_checkint(L, 2);

	if (pageno < 1 || pageno > ddjvu_document_get_pagenum(doc->doc_ref)) {
		return luaL_error(L, "cannot open page #%d, out of range (1-%d)", pageno, ddjvu_document_get_pagenum(doc->doc_ref));
	}

	DjvuPage *page = (DjvuPage*) lua_newuserdata(L, sizeof(DjvuPage));
	luaL_getmetatable(L, "djvupage");
	lua_setmetatable(L, -2);

	/* djvulibre counts page starts from 0 */
	page->page_ref = ddjvu_page_create_by_pageno(doc->doc_ref, pageno - 1);
	if (! page->page_ref)
		return luaL_error(L, "cannot open page #%d", pageno);
	while (! ddjvu_page_decoding_done(page->page_ref))
		handle(L, doc->context, TRUE);

	page->doc = doc;
	page->num = pageno;

	/* djvulibre counts page starts from 0 */
	while((r=ddjvu_document_get_pageinfo(doc->doc_ref, pageno - 1,
										&(page->info)))<DDJVU_JOB_OK)
		handle(L, doc->context, TRUE);
	if (r>=DDJVU_JOB_FAILED)
		return luaL_error(L, "cannot get page #%d information", pageno);

	return 1;
}

/* get page size after zoomed */
static int getPageSize(lua_State *L) {
	DjvuPage *page = (DjvuPage*) luaL_checkudata(L, 1, "djvupage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	
	lua_pushnumber(L, dc->zoom * page->info.width);
	lua_pushnumber(L, dc->zoom * page->info.height);

	return 2;
}

/* unsupported so fake it */
static int getUsedBBox(lua_State *L) {
	lua_pushnumber(L, (double)0.01);
	lua_pushnumber(L, (double)0.01);
	lua_pushnumber(L, (double)-0.01);
	lua_pushnumber(L, (double)-0.01);
	return 4;
}

static int getOriginalPageSize(lua_State *L) {
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");
	int pageno = luaL_checkint(L, 2);

	ddjvu_status_t r;
	ddjvu_pageinfo_t info;

	while ((r=ddjvu_document_get_pageinfo(
				   doc->doc_ref, pageno-1, &info))<DDJVU_JOB_OK) {
		handle(L, doc->context, TRUE);
	}

	lua_pushnumber(L, info.width);
	lua_pushnumber(L, info.height);

	return 2;
}

static int getPageInfo(lua_State *L) {
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");
	int pageno = luaL_checkint(L, 2);
	ddjvu_page_t *djvu_page;
	int page_width, page_height, page_dpi;
	double page_gamma;
	ddjvu_page_type_t page_type;
	char *page_type_str;

	djvu_page = ddjvu_page_create_by_pageno(doc->doc_ref, pageno - 1);
	if (! djvu_page)
		return luaL_error(L, "cannot create djvu_page #%d", pageno);

	while (! ddjvu_page_decoding_done(djvu_page))
		handle(L, doc->context, TRUE);

	page_width = ddjvu_page_get_width(djvu_page);
	lua_pushnumber(L, page_width);

	page_height = ddjvu_page_get_height(djvu_page);
	lua_pushnumber(L, page_height);

	page_dpi = ddjvu_page_get_resolution(djvu_page);
	lua_pushnumber(L, page_dpi);

	page_gamma = ddjvu_page_get_gamma(djvu_page);
	lua_pushnumber(L, page_gamma);

	page_type = ddjvu_page_get_type(djvu_page);
	switch (page_type) {
		case DDJVU_PAGETYPE_UNKNOWN:
			page_type_str = "UNKNOWN";
			break;

		case DDJVU_PAGETYPE_BITONAL:
			page_type_str = "BITONAL";
			break;

		case DDJVU_PAGETYPE_PHOTO:
			page_type_str = "PHOTO";
			break;

		case DDJVU_PAGETYPE_COMPOUND:
			page_type_str = "COMPOUND";
			break;

		default:
			page_type_str = "INVALID";
			break;
	}
	lua_pushstring(L, page_type_str);

	ddjvu_page_release(djvu_page);

	return 5;
}

/*
 * Return a table like following:
 * {
 *    -- a line entry
 *    1 = {
 *       1 = {word="This", x0=377, y0=4857, x1=2427, y1=5089},
 *       2 = {word="is", x0=377, y0=4857, x1=2427, y1=5089},
 *       3 = {word="Word", x0=377, y0=4857, x1=2427, y1=5089},
 *       4 = {word="List", x0=377, y0=4857, x1=2427, y1=5089},
 *       x0 = 377, y0 = 4857, x1 = 2427, y1 = 5089,
 *    },
 *
 *    -- an other line entry
 *    2 = {
 *       1 = {word="This", x0=377, y0=4857, x1=2427, y1=5089},
 *       2 = {word="is", x0=377, y0=4857, x1=2427, y1=5089},
 *       x0 = 377, y0 = 4857, x1 = 2427, y1 = 5089,
 *    },
 * }
 */
static int getPageText(lua_State *L) {
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");
	int pageno = luaL_checkint(L, 2);

	/* get page height for coordinates transform */
	ddjvu_pageinfo_t info;
	ddjvu_status_t r;
	while ((r=ddjvu_document_get_pageinfo(
				   doc->doc_ref, pageno-1, &info))<DDJVU_JOB_OK) {
		handle(L, doc->context, TRUE);
	}
	if (r>=DDJVU_JOB_FAILED)
		return luaL_error(L, "cannot get page #%d information", pageno);

	/* start retrieving page text */
	miniexp_t sexp, se_line, se_word;
	int i = 1, j = 1, counter_l = 1, counter_w=1,
		nr_line = 0, nr_word = 0;
	const char *word = NULL;
	
	while ((sexp = ddjvu_document_get_pagetext(doc->doc_ref, pageno-1, "word"))
				== miniexp_dummy) {
		handle(L, doc->context, True);
	}

	/* throuw page info and obtain lines info, after this, sexp's entries
	 * are lines. */
	sexp = miniexp_cdr(sexp);
	/* get number of lines in a page */
	nr_line = miniexp_length(sexp);
	/* table that contains all the lines */
	lua_newtable(L);

	counter_l = 1;
	for(i = 1; i <= nr_line; i++) {
		/* retrive one line entry */
		se_line = miniexp_nth(i, sexp);
		nr_word = miniexp_length(se_line);
		if (nr_word == 0) {
			continue;
		}

		/* subtable that contains words in a line */
		lua_pushnumber(L, counter_l);
		lua_newtable(L);
		counter_l++;

		/* set line position */
		lua_pushstring(L, "x0");
		lua_pushnumber(L, miniexp_to_int(miniexp_nth(1, se_line)));
		lua_settable(L, -3);

		lua_pushstring(L, "y1");
		lua_pushnumber(L,
				info.height - miniexp_to_int(miniexp_nth(2, se_line)));
		lua_settable(L, -3);

		lua_pushstring(L, "x1");
		lua_pushnumber(L, miniexp_to_int(miniexp_nth(3, se_line)));
		lua_settable(L, -3);

		lua_pushstring(L, "y0");
		lua_pushnumber(L,
				info.height - miniexp_to_int(miniexp_nth(4, se_line)));
		lua_settable(L, -3);

		/* now loop through each word in the line */
		counter_w = 1;
		for(j = 1; j <= nr_word; j++) {
			/* retrive one word entry */
			se_word = miniexp_nth(j, se_line);
			/* check to see whether the entry is empty */
			word = miniexp_to_str(miniexp_nth(5, se_word));
			if (!word) {
				continue;
			}

			/* create table that contains info for a word */
			lua_pushnumber(L, counter_w);
			lua_newtable(L);
			counter_w++;

			/* set word info */
			lua_pushstring(L, "x0");
			lua_pushnumber(L, miniexp_to_int(miniexp_nth(1, se_word)));
			lua_settable(L, -3);

			lua_pushstring(L, "y1");
			lua_pushnumber(L,
					info.height - miniexp_to_int(miniexp_nth(2, se_word)));
			lua_settable(L, -3);

			lua_pushstring(L, "x1");
			lua_pushnumber(L, miniexp_to_int(miniexp_nth(3, se_word)));
			lua_settable(L, -3);

			lua_pushstring(L, "y0");
			lua_pushnumber(L,
					info.height - miniexp_to_int(miniexp_nth(4, se_word)));
			lua_settable(L, -3);

			lua_pushstring(L, "word");
			lua_pushstring(L, word);
			lua_settable(L, -3);

			/* set word entry to line subtable */
			lua_settable(L, -3);
		} /* end of for (j) */

		/* set line entry to page text table */
		lua_settable(L, -3);
	} /* end of for (i) */

	return 1;
}

static int closePage(lua_State *L) {
	DjvuPage *page = (DjvuPage*) luaL_checkudata(L, 1, "djvupage");

	// should be safe if called twice
	if (page->page_ref != NULL) {
		ddjvu_page_release(page->page_ref);
		page->page_ref = NULL;
	}
	return 0;
}

static int reflowPage(lua_State *L) {

	DjvuPage *page = (DjvuPage*) luaL_checkudata(L, 1, "djvupage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	ddjvu_render_mode_t mode = (int) luaL_checkint(L, 3);

	int width, height;
	k2pdfopt_djvu_reflow(page->page_ref, page->doc->context, mode, page->doc->pixelformat, dc->zoom);
	k2pdfopt_rfbmp_size(&width, &height);
	k2pdfopt_rfbmp_zoom(&dc->zoom);

	lua_pushnumber(L, (double)width);
	lua_pushnumber(L, (double)height);
	lua_pushnumber(L, (double)dc->zoom);

	return 3;
}

static int drawReflowedPage(lua_State *L) {
	uint8_t *pmptr = NULL;

	DjvuPage *page = (DjvuPage*) luaL_checkudata(L, 1, "djvupage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 3, "blitbuffer");

	uint8_t *bbptr = bb->data;
	k2pdfopt_rfbmp_ptr(&pmptr);

	int x_offset = 0;
	int y_offset = 0;

	bbptr += bb->pitch * y_offset;
	int x, y;
	for(y = y_offset; y < bb->h; y++) {
		for(x = x_offset/2; x < (bb->w/2); x++) {
			int p = x*2 - x_offset;
			bbptr[x] = (((pmptr[p + 1] & 0xF0) >> 4) | (pmptr[p] & 0xF0)) ^ 0xFF;
		}
		bbptr += bb->pitch;
		pmptr += bb->w;
		if (bb->w & 1) {
			bbptr[x] = 255 - (pmptr[x*2] & 0xF0);
		}
	}

	return 0;
}

static int drawPage(lua_State *L) {
	DjvuPage *page = (DjvuPage*) luaL_checkudata(L, 1, "djvupage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 3, "blitbuffer");
	ddjvu_render_mode_t djvu_render_mode = (int) luaL_checkint(L, 6);
	unsigned char adjusted_low[16], adjusted_high[16];
	int i, adjust_pixels = 0;
	ddjvu_rect_t pagerect, renderrect;
	int bbsize = (bb->w)*(bb->h)+1;
	uint8_t *imagebuffer = malloc(bbsize);

	/*printf("@page %d, @@zoom:%f, offset: (%d, %d)\n", page->num, dc->zoom, dc->offset_x, dc->offset_y);*/

	/* render full page into rectangle specified by pagerect */
	pagerect.x = 0;
	pagerect.y = 0;
	pagerect.w = page->info.width * dc->zoom;
	pagerect.h = page->info.height * dc->zoom;

	/*printf("--pagerect--- (x: %d, y: %d), w: %d, h: %d.\n", 0, 0, pagerect.w, pagerect.h);*/

	/* copy pixels area from pagerect specified by renderrect.
	 *
	 * ddjvulibre library does not support negative offset, positive offset
	 * means moving towards right and down.
	 *
	 * However, djvureader.lua handles offset differently. It uses negative
	 * offset to move right and down while positive offset to move left
	 * and up. So we need to handle positive offset manually when copying
	 * imagebuffer to blitbuffer (framebuffer).
	 */
	renderrect.x = MAX(-dc->offset_x, 0);
	renderrect.y = MAX(-dc->offset_y, 0);
	renderrect.w = MIN(pagerect.w - renderrect.x, bb->w);
	renderrect.h = MIN(pagerect.h - renderrect.y, bb->h);

	/*printf("--renderrect--- (%d, %d), w:%d, h:%d\n", renderrect.x, renderrect.y, renderrect.w, renderrect.h);*/

	/* ddjvulibre library only supports rotation of 0, 90, 180 and 270 degrees.
	 * These four kinds of rotations can already be achieved by native system.
	 * So we don't set rotation here.
	 */

	if (!ddjvu_page_render(page->page_ref, djvu_render_mode, &pagerect, &renderrect, page->doc->pixelformat, bb->w, imagebuffer))
		memset(imagebuffer, 0xFF, bbsize);

	uint8_t *bbptr = bb->data;
	uint8_t *pmptr = imagebuffer;
	int x, y;
	/* if offset is positive, we are moving towards up and left. */
	int x_offset = MAX(0, dc->offset_x);
	int y_offset = MAX(0, dc->offset_y);

	/* prepare the tables for adjusting the intensity of pixels */
	if (dc->gamma != -1.0) {
		for (i=0; i<16; i++) {
			adjusted_low[i] = MIN(15, (unsigned char)floorf(dc->gamma * (float)i));
			adjusted_high[i] = adjusted_low[i] << 4;
		}
		adjust_pixels = 1;
	}

	bbptr += bb->pitch * y_offset;
	for(y = y_offset; y < bb->h; y++) {
		/* bbptr's line width is half of pmptr's */
		for(x = x_offset/2; x < (bb->w / 2); x++) {
			int p = x*2 - x_offset;
			unsigned char low = 15 - (pmptr[p + 1] >> 4);
			unsigned char high = 15 - (pmptr[p] >> 4);
			if (adjust_pixels)
				bbptr[x] = adjusted_high[high] | adjusted_low[low];
			else
				bbptr[x] = (high << 4) | low;
		}
		if (bb->w & 1) {
			bbptr[x] = 255 - (pmptr[x*2] & 0xF0);
		}
		/* go to next line */
		bbptr += bb->pitch;
		pmptr += bb->w;
	}

	free(imagebuffer);
	return 0;
}

static int getCacheSize(lua_State *L) {
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");
	unsigned long size = ddjvu_cache_get_size(doc->context);
	//printf("## ddjvu_cache_get_size = %d\n", (int)size);
	lua_pushnumber(L, size);
	return 1;
}

static int cleanCache(lua_State *L) {
	DjvuDocument *doc = (DjvuDocument*) luaL_checkudata(L, 1, "djvudocument");
	//printf("## ddjvu_cache_clear\n");
	ddjvu_cache_clear(doc->context);
	return 0;
}

static const struct luaL_Reg djvu_func[] = {
	{"openDocument", openDocument},
	{NULL, NULL}
};

static const struct luaL_Reg djvudocument_meth[] = {
	{"openPage", openPage},
	{"getPages", getNumberOfPages},
	{"getToc", getTableOfContent},
	{"getPageText", getPageText},
	{"getOriginalPageSize", getOriginalPageSize},
	{"getPageInfo", getPageInfo},
	{"close", closeDocument},
	{"getCacheSize", getCacheSize},
	{"cleanCache", cleanCache},
	{"__gc", closeDocument},
	{NULL, NULL}
};

static const struct luaL_Reg djvupage_meth[] = {
	{"getSize", getPageSize},
	{"getUsedBBox", getUsedBBox},
	{"close", closePage},
	{"__gc", closePage},
	{"reflow", reflowPage},
	{"rfdraw", drawReflowedPage},
	{"draw", drawPage},
	{NULL, NULL}
};

int luaopen_djvu(lua_State *L) {
	luaL_newmetatable(L, "djvudocument");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, djvudocument_meth);
	lua_pop(L, 1);

	luaL_newmetatable(L, "djvupage");
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);
	luaL_register(L, NULL, djvupage_meth);
	lua_pop(L, 1);

	luaL_register(L, "djvu", djvu_func);
	return 1;
}
