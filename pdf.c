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
#include <fitz/fitz-internal.h>

#include "blitbuffer.h"
#include "drawcontext.h"
#include "pdf.h"
#include <stdio.h>
#include <math.h>
#include <stddef.h>


typedef struct PdfDocument {
	fz_document *xref;
	fz_context *context;
} PdfDocument;

typedef struct PdfPage {
	int num;
#ifdef USE_DISPLAY_LIST
	fz_display_list *list;
#endif
	fz_page *page;
	PdfDocument *doc;
} PdfPage;


static double LOG_TRESHOLD_PERC = 0.05; // 5%

enum {
    MAGIC = 0x3795d42b,
};

typedef struct header {
    int magic;
    size_t sz;
} header;

static size_t msize=0;
static size_t msize_prev;
static size_t msize_max;
static size_t msize_min;
static size_t msize_iniz;
static int is_realloc=0;

#if 0
char* readable_fs(double size/*in bytes*/, char *buf) {
    int i = 0;
    const char* units[] = {"B", "kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"};
    while (size > 1024) {
        size /= 1024;
        i++;
    }
    sprintf(buf, "%.*f %s", i, size, units[i]);
    return buf;
}
#endif

static void resetMsize(){
	msize_iniz = msize;
	msize_prev = 0;
	msize_max = 0;
	msize_min = (size_t)-1;
}

static void showMsize(){
	char buf[15],buf2[15],buf3[15],buf4[15];
	//printf("§§§ now: %s was: %s - min: %s - max: %s\n",readable_fs(msize,buf),readable_fs(msize_iniz,buf2),readable_fs(msize_min,buf3),readable_fs(msize_max,buf4));
	resetMsize();
}

static void log_size(char *funcName){
	if(msize_max < msize)
		msize_max = msize;
	if(msize_min > msize)
		msize_min = msize;
	if(1==0 && abs(msize-msize_prev)>msize_prev*LOG_TRESHOLD_PERC){
		char buf[15],buf2[15];
		//printf("§§§ %s - total: %s (was %s)\n",funcName, readable_fs(msize,buf),readable_fs(msize_prev,buf2));
		msize_prev = msize;
	}
}

static void *
my_malloc_default(void *opaque, unsigned int size)
{
    struct header * h = malloc(size + sizeof(header));
    if (h == NULL)
         return NULL;

    h -> magic = MAGIC;
    h -> sz = size;
    msize += size + sizeof(struct header);
    if(is_realloc!=1)
	    log_size("alloc");
    return (void *)(h + 1);
}

static void
my_free_default(void *opaque, void *ptr)
{
   if (ptr != NULL) {
        struct header * h = ((struct header *)ptr) - 1;
        if (h -> magic != MAGIC) { /* Not allocated by us */
        } else {
            msize -= h -> sz + sizeof(struct header);
            free(h);
        }
   }
   if(is_realloc!=1)
	   log_size("free");
}

static void *
my_realloc_default(void *opaque, void *old, unsigned int size)
{
	void * newp;
    if (old==NULL) { //practically, it's a malloc
    	newp = my_malloc_default(opaque, size);
    } else {
    	struct header * h = ((struct header *)old) - 1;
		if (h -> magic != MAGIC) { // Not allocated by my_malloc_default
			//printf("§§§ warn: not allocated by my_malloc_default, new size: %i\n",size);
			newp = realloc(old,size);
		} else { // malloc + free
			is_realloc = 1;
			size_t oldsize = h -> sz;
			//printf("realloc %i -> %i\n",oldsize,size);
			newp = my_malloc_default(opaque, size);
			if (NULL != newp) {
				memcpy(newp, old, oldsize<size?oldsize:size);
				my_free_default(opaque, old);
			}
			log_size("realloc");
			is_realloc = 0;
		}
	}

	return(newp);
}

fz_alloc_context my_alloc_default =
{
	NULL,
	my_malloc_default,
	my_realloc_default,
	my_free_default
};



static int openDocument(lua_State *L) {
	char *filename = strdup(luaL_checkstring(L, 1));
	int cache_size = luaL_optint(L, 2, 64 << 20); // 64 MB limit default
	char buf[15];
	//printf("## cache_size: %s\n",readable_fs(cache_size,buf));

	PdfDocument *doc = (PdfDocument*) lua_newuserdata(L, sizeof(PdfDocument));

	luaL_getmetatable(L, "pdfdocument");
	lua_setmetatable(L, -2);

	doc->context = fz_new_context(&my_alloc_default, NULL, cache_size);

	fz_try(doc->context) {
		doc->xref = fz_open_document(doc->context, filename);
	}
	fz_catch(doc->context) {
		free(filename);
		return luaL_error(L, "cannot open PDF file");
	}

	free(filename);
	return 1;
}

static int needsPassword(lua_State *L) {
	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");
	lua_pushboolean(L, fz_needs_password(doc->xref));
	return 1;
}

static int authenticatePassword(lua_State *L) {
	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");
	char *password = strdup(luaL_checkstring(L, 2));

	if (!fz_authenticate_password(doc->xref, password)) {
		lua_pushboolean(L, 0);
	} else {
		lua_pushboolean(L, 1);
	}
	free(password);
	return 1;
}

static int closeDocument(lua_State *L) {
	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");

	// should be save if called twice
	if(doc->xref != NULL) {
		fz_close_document(doc->xref);
		doc->xref = NULL;
	}
	if(doc->context != NULL) {
		fz_free_context(doc->context);
		doc->context = NULL;
	}

	return 0;
}

static int getNumberOfPages(lua_State *L) {
	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");
	fz_try(doc->context) {
		lua_pushinteger(L, fz_count_pages(doc->xref));
	}
	fz_catch(doc->context) {
		return luaL_error(L, "cannot access page tree");
	}
	return 1;
}

/*
 * helper function for getTableOfContent()
 */
static int walkTableOfContent(lua_State *L, fz_outline* ol, int *count, int depth) {
	depth++;
	while(ol) {
		lua_pushnumber(L, *count);

		/* set subtable */
		lua_newtable(L);
		lua_pushstring(L, "page");
		lua_pushnumber(L, ol->dest.ld.gotor.page + 1);
		lua_settable(L, -3);

		lua_pushstring(L, "depth");
		lua_pushnumber(L, depth);
		lua_settable(L, -3);

		lua_pushstring(L, "title");
		lua_pushstring(L, ol->title);
		lua_settable(L, -3);


		lua_settable(L, -3);
		(*count)++;
		if (ol->down) {
			walkTableOfContent(L, ol->down, count, depth);
		}
		ol = ol->next;
	}
	return 0;
}

/*
 * Return a table like this:
 * {
 *		{page=12, depth=1, title="chapter1"},
 *		{page=54, depth=1, title="chapter2"},
 * }
 */
static int getTableOfContent(lua_State *L) {
	fz_outline *ol;
	int count = 1;

	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");
	ol = fz_load_outline(doc->xref);

	lua_newtable(L);
	walkTableOfContent(L, ol, &count, 0);
	return 1;
}

static int openPage(lua_State *L) {
	fz_device *dev;

	PdfDocument *doc = (PdfDocument*) luaL_checkudata(L, 1, "pdfdocument");

	int pageno = luaL_checkint(L, 2);

	fz_try(doc->context) {
		if(pageno < 1 || pageno > fz_count_pages(doc->xref)) {
			return luaL_error(L, "cannot open page #%d, out of range (1-%d)",
					pageno, fz_count_pages(doc->xref));
		}

		PdfPage *page = (PdfPage*) lua_newuserdata(L, sizeof(PdfPage));

		luaL_getmetatable(L, "pdfpage");
		lua_setmetatable(L, -2);

		page->page = fz_load_page(doc->xref, pageno - 1);

		page->doc = doc;
	}
	fz_catch(doc->context) {
		return luaL_error(L, "cannot open page #%d", pageno);
	}
	showMsize();
	return 1;
}

static void load_lua_text_page(lua_State *L, fz_text_page *page)
{
	fz_text_block *block;
	fz_text_line *aline;
	fz_text_span *span;

	fz_rect bbox, linebbox;
	int i;
	int word, line;
	int len, c;
	int start;
	char chars[4]; // max length of UTF-8 encoded rune
	luaL_Buffer textbuf;

	/* table that contains all the lines */
	lua_newtable(L);

	line = 1;

	for (block = page->blocks; block < page->blocks + page->len; block++)
	{
		for (aline = block->lines; aline < block->lines + block->len; aline++)
		{
			linebbox = fz_empty_rect;
			/* will hold information about a line: */
			lua_newtable(L);

			word = 1;

			for (span = aline->spans; span < aline->spans + aline->len; span++)
			{
				for(i = 0; i < span->len; ) {
					/* will hold information about a word: */
					lua_newtable(L);

					luaL_buffinit(L, &textbuf);
					bbox = span->text[i].bbox; // start with sensible default
					for(; i < span->len; i++) {
						/* check for space characters */
						if(span->text[i].c == ' ' ||
							span->text[i].c == '\t' ||
							span->text[i].c == '\n' ||
							span->text[i].c == '\v' ||
							span->text[i].c == '\f' ||
							span->text[i].c == '\r' ||
							span->text[i].c == 0xA0 ||
							span->text[i].c == 0x1680 ||
							span->text[i].c == 0x180E ||
							(span->text[i].c >= 0x2000 && span->text[i].c <= 0x200A) ||
							span->text[i].c == 0x202F ||
							span->text[i].c == 0x205F ||
							span->text[i].c == 0x3000) {
							// ignore and end word
							i++;
							break;
						}
						len = fz_runetochar(chars, span->text[i].c);
						for(c = 0; c < len; c++) {
							luaL_addchar(&textbuf, chars[c]);
						}
						bbox = fz_union_rect(bbox, span->text[i].bbox);
						linebbox = fz_union_rect(linebbox, span->text[i].bbox);
					}
					lua_pushstring(L, "word");
					luaL_pushresult(&textbuf);
					lua_settable(L, -3);

					/* bbox for a word: */
					lua_pushstring(L, "x0");
					lua_pushinteger(L, bbox.x0);
					lua_settable(L, -3);
					lua_pushstring(L, "y0");
					lua_pushinteger(L, bbox.y0);
					lua_settable(L, -3);
					lua_pushstring(L, "x1");
					lua_pushinteger(L, bbox.x1);
					lua_settable(L, -3);
					lua_pushstring(L, "y1");
					lua_pushinteger(L, bbox.y1);
					lua_settable(L, -3);

					lua_rawseti(L, -2, word++);
				}
			}
			/* bbox for a whole line */
			lua_pushstring(L, "x0");
			lua_pushinteger(L, linebbox.x0);
			lua_settable(L, -3);
			lua_pushstring(L, "y0");
			lua_pushinteger(L, linebbox.y0);
			lua_settable(L, -3);
			lua_pushstring(L, "x1");
			lua_pushinteger(L, linebbox.x1);
			lua_settable(L, -3);
			lua_pushstring(L, "y1");
			lua_pushinteger(L, linebbox.y1);
			lua_settable(L, -3);

			lua_rawseti(L, -2, line++);
		}
	}
}

/* get the text of the given page
 *
 * will return text in a Lua table that is modeled after
 * djvu.c creates this table.
 *
 * note that the definition of "line" is somewhat arbitrary
 * here (for now)
 *
 * MuPDFs API provides text as single char information
 * that is collected in "spans". we use a span as a "line"
 * in Lua output and segment spans into words by looking
 * for space characters.
 *
 * will return an empty table if we have no text
 */
static int getPageText(lua_State *L) {
	fz_text_page *text_page;
	fz_text_sheet *text_sheet;
	fz_device *tdev;

	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");

	text_page = fz_new_text_page(page->doc->context, fz_bound_page(page->doc->xref, page->page));
	text_sheet = fz_new_text_sheet(page->doc->context);
	tdev = fz_new_text_device(page->doc->context, text_sheet, text_page);
	fz_run_page(page->doc->xref, page->page, tdev, fz_identity, NULL);
	fz_free_device(tdev);
	tdev = NULL;

	load_lua_text_page(L, text_page);

	fz_free_text_page(page->doc->context, text_page);
	fz_free_text_sheet(page->doc->context, text_sheet);

	return 1;
}

static int getPageSize(lua_State *L) {
	fz_matrix ctm;
	fz_rect bounds;
	fz_rect bbox;
	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");

	bounds = fz_bound_page(page->doc->xref, page->page);
	ctm = fz_scale(dc->zoom, dc->zoom) ;
	ctm = fz_concat(ctm, fz_rotate(dc->rotate));
	bbox = fz_transform_rect(ctm, bounds);

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

	fz_try(page->doc->context) {
		dev = fz_new_bbox_device(page->doc->context, &result);
		fz_run_page(page->doc->xref, page->page, dev, ctm, NULL);
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
		fz_free_page(page->doc->xref, page->page);
		page->page = NULL;
	}
	return 0;
}

static int reflowPage(lua_State *L) {

	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	int width  = luaL_checkint(L, 4); // framebuffer size
	int height = luaL_checkint(L, 5);
	double font_size = luaL_checknumber(L, 6);
	double page_margin = luaL_checknumber(L, 7);
	double line_spacing = luaL_checknumber(L, 8);
	double word_spacing = luaL_checknumber(L, 9);
	int text_wrap = luaL_checkint(L, 10);
	int straighten = luaL_checkint(L, 11);
	int justification = luaL_checkint(L, 12);
	int detect_indent = luaL_checkint(L, 13);
	int columns = luaL_checkint(L, 14);
	double contrast = luaL_checknumber(L, 15);
	int rotation = luaL_checkint(L, 16);
	double quality = luaL_checknumber(L, 17);
	double defect_size = luaL_checknumber(L, 18);
	int trim_page = luaL_checkint(L, 19);

	k2pdfopt_set_params(width, height, font_size, page_margin, line_spacing, word_spacing, \
			text_wrap, straighten, justification, detect_indent, columns, contrast, rotation, \
			quality, defect_size, trim_page);
	k2pdfopt_mupdf_reflow(page->doc->xref, page->page, page->doc->context);
	k2pdfopt_rfbmp_size(&width, &height);
	k2pdfopt_rfbmp_zoom(&dc->zoom);

	lua_pushnumber(L, (double)width);
	lua_pushnumber(L, (double)height);
	lua_pushnumber(L, (double)dc->zoom);

	return 3;
}

static int drawReflowedPage(lua_State *L) {
	uint8_t *pmptr = NULL;

	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");
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
	fz_pixmap *pix;
	fz_device *dev;
	fz_matrix ctm;
	fz_bbox bbox;

	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");
	DrawContext *dc = (DrawContext*) luaL_checkudata(L, 2, "drawcontext");
	BlitBuffer *bb = (BlitBuffer*) luaL_checkudata(L, 3, "blitbuffer");
	bbox.x0 = luaL_checkint(L, 4);
	bbox.y0 = luaL_checkint(L, 5);
	bbox.x1 = bbox.x0 + bb->w;
	bbox.y1 = bbox.y0 + bb->h;
	pix = fz_new_pixmap_with_bbox(page->doc->context, fz_device_gray, bbox);
	fz_clear_pixmap_with_value(page->doc->context, pix, 0xff);

	ctm = fz_scale(dc->zoom, dc->zoom);
	ctm = fz_concat(ctm, fz_rotate(dc->rotate));
	ctm = fz_concat(ctm, fz_translate(dc->offset_x, dc->offset_y));
	dev = fz_new_draw_device(page->doc->context, pix);
#ifdef MUPDF_TRACE
	fz_device *tdev;
	fz_try(page->doc->context) {
		tdev = fz_new_trace_device(page->doc->context);
		fz_run_page(page->doc->xref, page->page, tdev, ctm, NULL);
	}
	fz_always(page->doc->context) {
		fz_free_device(tdev);
	}
#endif
	fz_run_page(page->doc->xref, page->page, dev, ctm, NULL);
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
			bbptr[x] = (pmptr[x*2] & 0xF0) ^ 0xF0;
		}
		bbptr += bb->pitch;
		pmptr += bb->w;
	}

	fz_drop_pixmap(page->doc->context, pix);

	return 0;
}

static int getCacheSize(lua_State *L) {
	//printf("## mupdf getCacheSize = %zu\n", msize);
	lua_pushnumber(L, msize);
	return 1;
}

static int cleanCache(lua_State *L) {
	//printf("## mupdf cleanCache NOP\n");
	return 0;
}


static int getPageLinks(lua_State *L) {
	fz_link *page_links;
	fz_link *link;

	int link_count;

	PdfPage *page = (PdfPage*) luaL_checkudata(L, 1, "pdfpage");

	page_links = fz_load_links(page->doc->xref, page->page); // page->doc->xref?

	lua_newtable(L); // all links

	link_count = 0;

	for (link = page_links; link; link = link->next) {
		lua_newtable(L); // new link

		lua_pushstring(L, "x0");
		lua_pushinteger(L, link->rect.x0);
		lua_settable(L, -3);
		lua_pushstring(L, "y0");
		lua_pushinteger(L, link->rect.y0);
		lua_settable(L, -3);
		lua_pushstring(L, "x1");
		lua_pushinteger(L, link->rect.x1);
		lua_settable(L, -3);
		lua_pushstring(L, "y1");
		lua_pushinteger(L, link->rect.y1);
		lua_settable(L, -3);

		if (link->dest.kind == FZ_LINK_URI) {
			lua_pushstring(L, "uri");
			lua_pushstring(L, link->dest.ld.uri.uri);
			lua_settable(L, -3);
		} else if (link->dest.kind == FZ_LINK_GOTO) {
			lua_pushstring(L, "page");
			lua_pushinteger(L, link->dest.ld.gotor.page); // FIXME page+1?
			lua_settable(L, -3);
		} else {
			printf("ERROR: unkown link kind: %x", link->dest.kind);
		}

		lua_rawseti(L, -2, ++link_count);
    }

	//printf("## getPageLinks found %d links in document\n", link_count);

	fz_drop_link(page->doc->context, page_links);

	return 1;
}

static const struct luaL_Reg pdf_func[] = {
	{"openDocument", openDocument},
	{NULL, NULL}
};

static const struct luaL_Reg pdfdocument_meth[] = {
	{"needsPassword", needsPassword},
	{"authenticatePassword", authenticatePassword},
	{"openPage", openPage},
	{"getPages", getNumberOfPages},
	{"getToc", getTableOfContent},
	{"close", closeDocument},
	{"getCacheSize", getCacheSize},
	{"cleanCache", cleanCache},
	{"__gc", closeDocument},
	{NULL, NULL}
};

static const struct luaL_Reg pdfpage_meth[] = {
	{"getSize", getPageSize},
	{"getUsedBBox", getUsedBBox},
	{"getPageText", getPageText},
	{"getPageLinks", getPageLinks},
	{"close", closePage},
	{"__gc", closePage},
	{"reflow", reflowPage},
	{"rfdraw", drawReflowedPage},
	{"draw", drawPage},
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
	luaL_register(L, "pdf", pdf_func);
	return 1;
}
