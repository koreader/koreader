/*
 ** k2pdfopt.c   K2pdfopt optimizes PDF/DJVU files for mobile e-readers
 **              (e.g. the Kindle) and smartphones. It works well on
 **              multi-column PDF/DJVU files. K2pdfopt is freeware.
 **
 ** Copyright (C) 2012  http://willus.com
 **
 ** This program is free software: you can redistribute it and/or modify
 ** it under the terms of the GNU Affero General Public License as
 ** published by the Free Software Foundation, either version 3 of the
 ** License, or (at your option) any later version.
 **
 ** This program is distributed in the hope that it will be useful,
 ** but WITHOUT ANY WARRANTY; without even the implied warranty of
 ** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 ** GNU Affero General Public License for more details.
 **
 ** You should have received a copy of the GNU Affero General Public License
 ** along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **
 /*
 ** WILLUSDEBUGX flags:
 ** 1 = Generic
 ** 2 = breakinfo row analysis
 ** 4 = word wrapping
 ** 8 = word wrapping II
 ** 16 = hyphens
 ** 32 = OCR
 **
 */
// #define WILLUSDEBUGX 32
// #define WILLUSDEBUG
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include <math.h>
#include "k2pdfopt.h"

#define HAVE_MUPDF

#define VERSION "v1.51"
#define GRAYLEVEL(r,g,b) ((int)(((r)*0.3+(g)*0.59+(b)*0.11)*1.002))
#if (defined(WIN32) || defined(WIN64))
#define TTEXT_BOLD    ANSI_WHITE
#define TTEXT_NORMAL  ANSI_NORMAL
#define TTEXT_BOLD2   ANSI_YELLOW
#define TTEXT_INPUT   ANSI_GREEN
#define TTEXT_WARN    ANSI_RED
#define TTEXT_HEADER  ANSI_CYAN
#define TTEXT_MAGENTA ANSI_MAGENTA
#else
#define TTEXT_BOLD    "\x1b[0m\x1b[34m"
#define TTEXT_NORMAL  "\x1b[0m"
#define TTEXT_BOLD2   "\x1b[0m\x1b[33m"
#define TTEXT_INPUT   "\x1b[0m\x1b[32m"
#define TTEXT_WARN    "\x1b[0m\x1b[31m"
#define TTEXT_HEADER  "\x1b[0m\x1b[36m"
#define TTEXT_MAGENTA "\x1b[0m\x1b[35m"
#endif

#ifndef __ANSI_H__
#define ANSI_RED            "\x1b[1m\x1b[31m"
#define ANSI_GREEN          "\x1b[1m\x1b[32m"
#define ANSI_YELLOW         "\x1b[1m\x1b[33m"
#define ANSI_BROWN          "\x1b[0m\x1b[33m"
#define ANSI_BLUE           "\x1b[1m\x1b[34m"
#define ANSI_MAGENTA        "\x1b[1m\x1b[35m"
#define ANSI_CYAN           "\x1b[1m\x1b[36m"
#define ANSI_WHITE          "\x1b[1m\x1b[37m"
#define ANSI_NORMAL         "\x1b[0m\x1b[37m"
#define ANSI_SAVE_CURSOR    "\x1b[s"
#define ANSI_RESTORE_CURSOR "\x1b[u"
#define ANSI_CLEAR_TO_END   "\x1b[K"
#define ANSI_BEGIN_LINE     "\x1b[80D"
#define ANSI_UP_ONE_LINE    "\x1b[1A"
#define ANSI_HOME           "\x1b[2J\x1b[0;0;H"
#define __ANSI_H__
#endif

/* bmp.c */
#define WILLUSBITMAP_TYPE_NATIVE       0
#define WILLUSBITMAP_TYPE_WIN32        1

#ifdef PI
#undef PI
#endif
/*
 ** Constants from the front of the CRC standard math tables
 ** (Accuracy = 50 digits)
 */
#define PI      3.14159265358979323846264338327950288419716939937511
#define SQRT2   1.41421356237309504880168872420969807856967187537695
#define SQRT3   1.73205080756887729352744634150587236694280525381039
#define LOG10E  0.43429448190325182765112891891660508229439700580367
#define DBPERNEP    (20.*LOG10E)

#define SRC_TYPE_PDF     1
#define SRC_TYPE_DJVU    2
#define SRC_TYPE_OTHER   3

/* DATA STRUCTURES */

typedef struct {
	int page; /* Source page */
	double rot_deg; /* Source rotation (happens first) */
	double x0, y0; /* x0,y0, in points, of lower left point on rectangle */
	double w, h; /* width and height of rectangle in points */
	double scale; /* Scale rectangle by this factor on destination page */
	double x1, y1; /* (x,y) position of lower left point on destination page, in points */
} PDFBOX;

typedef struct {
	PDFBOX *box;
	int n;
	int na;
} PDFBOXES;

typedef struct {
	int pageno; /* Source page number */
	double page_rot_deg; /* Source page rotation */
	PDFBOXES boxes;
} PAGEINFO;

typedef struct {
	int ch; /* Hyphen starting point -- < 0 for no hyphen */
	int c2; /* End of end region if hyphen is erased */
	int r1; /* Top of hyphen */
	int r2; /* Bottom of hyphen */
} HYPHENINFO;

typedef struct {
	int c1, c2; /* Left and right columns */
	int r1, r2; /* Top and bottom of region in pixels */
	int rowbase; /* Baseline of row */
	int gap; /* Gap to next region in pixels */
	int rowheight; /* text + gap */
	int capheight;
	int h5050;
	int lcheight;
	HYPHENINFO hyphen;
} TEXTROW;

typedef struct {
	TEXTROW *textrow;
	int rhmean_pixels; /* Mean row height (text) */
	int centered; /* Is this set of rows centered? */
	int n, na;
} BREAKINFO;

typedef struct {
	int red[256];
	int green[256];
	int blue[256];
	unsigned char *data; /* Top to bottom in native type, bottom to */
	/* top in Win32 type.                      */
	int width; /* Width of image in pixels */
	int height; /* Height of image in pixels */
	int bpp; /* Bits per pixel (only 8 or 24 allowed) */
	int size_allocated;
	int type; /* See defines above for WILLUSBITMAP_TYPE_... */
} WILLUSBITMAP;

typedef struct {
	int r1, r2; /* row position from top of bmp, inclusive */
	int c1, c2; /* column positions, inclusive */
	int rowbase; /* Baseline of text row */
	int capheight; /* capital letter height */
	int h5050;
	int lcheight; /* lower-case letter height */
	int bgcolor; /* 0 - 255 */
	HYPHENINFO hyphen;
	WILLUSBITMAP *bmp;
	WILLUSBITMAP *bmp8;
	WILLUSBITMAP *marked;
} BMPREGION;

typedef struct {
	WILLUSBITMAP bmp;
	int rows;
	int published_pages;
	int bgcolor;
	int fit_to_page;
	int wordcount;
	char debugfolder[256];
} MASTERINFO;

static int verbose = 0;
static int debug = 0;

#define DEFAULT_WIDTH 600
#define DEFAULT_HEIGHT 800
#define MIN_REGION_WIDTH_INCHES 1.0
#define SRCROT_AUTO   -999.
#define SRCROT_AUTOEP -998.

/*
 ** Blank Area Threshold Widths--average black pixel width, in inches, that
 ** prevents a region from being determined as "blank" or clear.
 */
static double gtc_in = .005; // detecting gap between columns
static double gtr_in = .006; // detecting gap between rows
static double gtw_in = .0015; // detecting gap between words
// static double gtm_in=.005; // detecting margins for trimming
static int src_left_to_right = 1;
static int src_whitethresh = -1;
static int dst_dpi = 167;
static int fit_columns = 1;
static int src_dpi = 300;
static int dst_width = DEFAULT_WIDTH; /* Full device width in pixels */
static int dst_height = DEFAULT_HEIGHT;
static int dst_userwidth = DEFAULT_WIDTH;
static int dst_userheight = DEFAULT_HEIGHT;
static int dst_justify = -1; // 0 = left, 1 = center
static int dst_figure_justify = -1; // -1 = same as dst_justify.  0=left 1=center 2=right
static double dst_min_figure_height_in = 0.75;
static int dst_fulljustify = -1; // 0 = no, 1 = yes
static int dst_color = 0;
static int dst_landscape = 0;
static double dst_mar = 0.06;
static double dst_martop = -1.0;
static double dst_marbot = -1.0;
static double dst_marleft = -1.0;
static double dst_marright = -1.0;
static double min_column_gap_inches = 0.1;
static double max_column_gap_inches = 1.5; // max gap between columns
static double min_column_height_inches = 1.5;
static double mar_top = -1.0;
static double mar_bot = -1.0;
static double mar_left = -1.0;
static double mar_right = -1.0;
static double max_region_width_inches = 3.6; /* Max viewable width (device width minus margins) */
static int max_columns = 2;
static double column_gap_range = 0.33;
static double column_offset_max = 0.2;
static double column_row_gap_height_in = 1. / 72.;
static int text_wrap = 1;
static double word_spacing = 0.375;
static double display_width_inches = 3.6; /* Device width = dst_width / dst_dpi */
static int column_fitted = 0;
static double lm_org, bm_org, tm_org, rm_org, dpi_org;
static double contrast_max = 2.0;
static int show_marked_source = 0;
static double defect_size_pts = 1.0;
static double max_vertical_gap_inches = 0.25;
static double vertical_multiplier = 1.0;
static double vertical_line_spacing = -1.2;
static double vertical_break_threshold = 1.75;
static int erase_vertical_lines = 0;
static int k2_hyphen_detect = 1;
static int dst_fit_to_page = 0;
/*
 ** Undocumented cmd-line args
 */
static double no_wrap_ar_limit = 0.2; /* -arlim */
static double no_wrap_height_limit_inches = 0.55; /* -whmax */
static double little_piece_threshold_inches = 0.5; /* -rwmin */
/*
 ** Keeping track of vertical gaps
 */
static double last_scale_factor_internal = -1.0;
/* indicates desired vert. gap before next region is added. */
static int last_rowbase_internal; /* Pixels between last text row baseline and current end */
/* of destination bitmap. */
static int beginning_gap_internal = -1;
static int last_h5050_internal = -1;
static int just_flushed_internal = 0;
static int gap_override_internal; /* If > 0, apply this gap in wrapbmp_flush() and then reset. */

void adjust_params_init(void);
void set_region_widths(void);
static void mark_source_page(BMPREGION *region, int caller_id, int mark_flags);
static void fit_column_to_screen(double column_width_inches);
static void restore_output_dpi(void);
void adjust_contrast(WILLUSBITMAP *src, WILLUSBITMAP *srcgrey, int *white);
static int bmpregion_row_black_count(BMPREGION *region, int r0);
static void bmpregion_row_histogram(BMPREGION *region);
static int bmpregion_find_multicolumn_divider(BMPREGION *region,
		int *row_black_count, BMPREGION *pageregion, int *npr, int *colcount,
		int *rowcount);
static int bmpregion_column_height_and_gap_test(BMPREGION *column,
		BMPREGION *region, int r1, int r2, int cmid, int *colcount,
		int *rowcount);
static int bmpregion_is_clear(BMPREGION *region, int *row_is_clear,
		double gt_in);
void bmpregion_multicolumn_add(BMPREGION *region, MASTERINFO *masterinfo,
		int level, PAGEINFO *pageinfo, int colgap0_pixels);
static void bmpregion_vertically_break(BMPREGION *region,
		MASTERINFO *masterinfo, int allow_text_wrapping, double force_scale,
		int *colcount, int *rowcount, PAGEINFO *pageinfo, int colgap_pixels,
		int ncols);
static void bmpregion_add(BMPREGION *region, BREAKINFO *breakinfo,
		MASTERINFO *masterinfo, int allow_text_wrapping, int trim_flags,
		int allow_vertical_breaks, double force_scale, int justify_flags,
		int caller_id, int *colcount, int *rowcount, PAGEINFO *pageinfo,
		int mark_flags, int rowbase_delta);
static void dst_add_gap_src_pixels(char *caller, MASTERINFO *masterinfo,
		int pixels);
static void dst_add_gap(MASTERINFO *masterinfo, double inches);
static void bmp_src_to_dst(MASTERINFO *masterinfo, WILLUSBITMAP *src,
		int justification_flags, int whitethresh, int nocr, int dpi);
static void bmp_fully_justify(WILLUSBITMAP *jbmp, WILLUSBITMAP *src, int nocr,
		int whitethresh, int just);
#ifdef HAVE_OCR
static void ocrwords_fill_in(OCRWORDS *words,WILLUSBITMAP *src,int whitethresh,int dpi);
#endif
static void bmpregion_trim_margins(BMPREGION *region, int *colcount0,
		int *rowcount0, int flags);
static void bmpregion_hyphen_detect(BMPREGION *region);
#if (WILLUSDEBUGX & 6)
static void breakinfo_echo(BREAKINFO *bi);
#endif
#if (defined(WILLUSDEBUGX) || defined(WILLUSDEBUG))
static void bmpregion_write(BMPREGION *region,char *filename);
#endif
static int height2_calc(int *rc, int n);
static void trim_to(int *count, int *i1, int i2, double gaplen);
static void bmpregion_analyze_justification_and_line_spacing(BMPREGION *region,
		BREAKINFO *breakinfo, MASTERINFO *masterinfo, int *colcount,
		int *rowcount, PAGEINFO *pageinfo, int allow_text_wrapping,
		double force_scale);
static int bmpregion_is_centered(BMPREGION *region, BREAKINFO *breakinfo,
		int i1, int i2, int *textheight);
static double median_val(double *x, int n);
static void bmpregion_find_vertical_breaks(BMPREGION *region,
		BREAKINFO *breakinfo, int *colcount, int *rowcount, double apsize_in);
static void textrow_assign_bmpregion(TEXTROW *textrow, BMPREGION *region);
static void breakinfo_compute_row_gaps(BREAKINFO *breakinfo, int r2);
static void breakinfo_compute_col_gaps(BREAKINFO *breakinfo, int c2);
static void breakinfo_remove_small_col_gaps(BREAKINFO *breakinfo, int lcheight,
		double mingap);
static void breakinfo_remove_small_rows(BREAKINFO *breakinfo, double fracrh,
		double fracgap, BMPREGION *region, int *colcount, int *rowcount);
static void breakinfo_alloc(int index, BREAKINFO *breakinfo, int nrows);
static void breakinfo_free(int index, BREAKINFO *breakinfo);
static void breakinfo_sort_by_gap(BREAKINFO *breakinfo);
static void breakinfo_sort_by_row_position(BREAKINFO *breakinfo);
static void bmpregion_one_row_find_breaks(BMPREGION *region,
		BREAKINFO *breakinfo, int *colcount, int *rowcount, int add_to_dbase);
void wrapbmp_init(void);
static int wrapbmp_ends_in_hyphen(void);
static void wrapbmp_set_color(int is_color);
static void wrapbmp_free(void);
static void wrapbmp_set_maxgap(int value);
static int wrapbmp_width(void);
static int wrapbmp_remaining(void);
static void wrapbmp_add(BMPREGION *region, int gap, int line_spacing, int rbase,
		int gio, int justification_flags);
static void wrapbmp_flush(MASTERINFO *masterinfo, int allow_full_justify,
		PAGEINFO *pageinfo, int use_bgi);
static void wrapbmp_hyphen_erase(void);
static void bmpregion_one_row_wrap_and_add(BMPREGION *region,
		BREAKINFO *breakinfo, int index, int i0, int i1, MASTERINFO *masterinfo,
		int justflags, int *colcount, int *rowcount, PAGEINFO *pageinfo,
		int rheight, int mean_row_gap, int rowbase, int marking_flags, int pi);
static void white_margins(WILLUSBITMAP *src, WILLUSBITMAP *srcgrey);
static void get_white_margins(BMPREGION *region);
/* Bitmap orientation detection functions */
static double bitmap_orientation(WILLUSBITMAP *bmp);
static double bmp_inflections_vertical(WILLUSBITMAP *srcgrey, int ndivisions,
		int delta, int *wthresh);
static double bmp_inflections_horizontal(WILLUSBITMAP *srcgrey, int ndivisions,
		int delta, int *wthresh);
static int inflection_count(double *x, int n, int delta, int *wthresh);
static void pdfboxes_init(PDFBOXES *boxes);
static void pdfboxes_free(PDFBOXES *boxes);
/*
 static void pdfboxes_add_box(PDFBOXES *boxes,PDFBOX *box);
 static void pdfboxes_delete(PDFBOXES *boxes,int n);
 */
static void word_gaps_add(BREAKINFO *breakinfo, int lcheight,
		double *median_gap);
static void bmp_detect_vertical_lines(WILLUSBITMAP *bmp, WILLUSBITMAP *cbmp,
		double dpi, double minwidth_in, double maxwidth_in, double minheight_in,
		double anglemax_deg, int white_thresh);
static int vert_line_erase(WILLUSBITMAP *bmp, WILLUSBITMAP *cbmp,
		WILLUSBITMAP *tmp, int row0, int col0, double tanthx,
		double minheight_in, double minwidth_in, double maxwidth_in,
		int white_thresh);
static void willus_dmem_alloc_warn(int index, void **ptr, int size,
		char *funcname, int exitcode);
static void willus_dmem_free(int index, double **ptr, char *funcname);
static int willus_mem_alloc_warn(void **ptr, int size, char *name, int exitcode);
static void willus_mem_free(double **ptr, char *name);
static void sortd(double *x, int n);
static void sorti(int *x, int n);
static void bmp_init(WILLUSBITMAP *bmap);
static int bmp_alloc(WILLUSBITMAP *bmap);
static void bmp_free(WILLUSBITMAP *bmap);
static int bmp_copy(WILLUSBITMAP *dest, WILLUSBITMAP *src);
static void bmp_fill(WILLUSBITMAP *bmp,int r,int g,int b);
static int bmp_bytewidth(WILLUSBITMAP *bmp);
static unsigned char *bmp_rowptr_from_top(WILLUSBITMAP *bmp, int row);
static void bmp_more_rows(WILLUSBITMAP *bmp, double ratio, int pixval);
static int bmp_is_grayscale(WILLUSBITMAP *bmp);
static int bmp_resample(WILLUSBITMAP *dest, WILLUSBITMAP *src, double x1,
		double y1, double x2, double y2, int newwidth, int newheight);
static void bmp_contrast_adjust(WILLUSBITMAP *dest,WILLUSBITMAP *src,double contrast);
static void bmp_convert_to_greyscale_ex(WILLUSBITMAP *dst, WILLUSBITMAP *src);
static int bmpmupdf_pixmap_to_bmp(WILLUSBITMAP *bmp, fz_context *ctx,
		fz_pixmap *pixmap);
static void handle(int wait, ddjvu_context_t *ctx);

static MASTERINFO _masterinfo, *masterinfo;
static int master_bmp_inited = 0;
static int master_bmp_width = 0;
static int master_bmp_height = 0;
static int max_page_width_pix = 3000;
static int max_page_height_pix = 4000;
static double shrink_factor = 0.9;
static double zoom_value = 1.0;

static void k2pdfopt_reflow_bmp(MASTERINFO *masterinfo, WILLUSBITMAP *src) {
	PAGEINFO _pageinfo, *pageinfo;
	WILLUSBITMAP _srcgrey, *srcgrey;
	int i, white, dpi;
	double area_ratio;

	masterinfo->debugfolder[0] = '\0';
	white = src_whitethresh; /* Will be set by adjust_contrast() or set to src_whitethresh */
	dpi = src_dpi;
	adjust_params_init();
	set_region_widths();

	srcgrey = &_srcgrey;
	if (master_bmp_inited == 0) {
		bmp_init(&masterinfo->bmp);
		master_bmp_inited = 1;
	}

	bmp_free(&masterinfo->bmp);
	bmp_init(&masterinfo->bmp);
	bmp_init(srcgrey);

	wrapbmp_init();

	int ii;
	masterinfo->bmp.bpp = 8;
	for (ii = 0; ii < 256; ii++)
		masterinfo->bmp.red[ii] = masterinfo->bmp.blue[ii] =
				masterinfo->bmp.green[ii] = ii;
	masterinfo->rows = 0;
	masterinfo->bmp.width = dst_width;
	area_ratio = 8.5 * 11.0 * dst_dpi * dst_dpi / (dst_width * dst_height);
	masterinfo->bmp.height = dst_height * area_ratio * 1.5;
	bmp_alloc(&masterinfo->bmp);
	bmp_fill(&masterinfo->bmp, 255, 255, 255);

	BMPREGION region;
	bmp_copy(srcgrey, src);
	adjust_contrast(src, srcgrey, &white);
	white_margins(src, srcgrey);

	region.r1 = 0;
	region.r2 = srcgrey->height - 1;
	region.c1 = 0;
	region.c2 = srcgrey->width - 1;
	region.bgcolor = white;
	region.bmp = src;
	region.bmp8 = srcgrey;

	masterinfo->bgcolor = white;
	masterinfo->fit_to_page = dst_fit_to_page;
	/* Check to see if master bitmap might need more room */
	bmpregion_multicolumn_add(&region, masterinfo, 1, pageinfo, (int) (0.25 * src_dpi + .5));

	master_bmp_width = masterinfo->bmp.width;
	master_bmp_height = masterinfo->rows;

	bmp_free(srcgrey);
}

void k2pdfopt_mupdf_reflow(fz_document *doc, fz_page *page, fz_context *ctx, \
		double zoom, double gamma, double rot_deg, \
		int bb_width, int bb_height, double line_space, double word_space) {
	fz_device *dev;
	fz_pixmap *pix;
	fz_rect bounds,bounds2;
	fz_matrix ctm;
	fz_bbox bbox;
	WILLUSBITMAP _src, *src;

	dst_userwidth  = bb_width; // dst_width is adjusted in adjust_params_init
	dst_userheight = bb_height;
	vertical_line_spacing = line_space;
	word_spacing = word_space;

	printf("k2pdfopt_mupdf_reflow width:%d height:%d, line space:%.2f, word space:%.2f\n", \
			bb_width,bb_height,vertical_line_spacing,word_spacing);

	double dpp;
	double dpi = 250*zoom;
	do {
		dpp = dpi / 72.;
		pix = NULL;
		fz_var(pix);
		bounds = fz_bound_page(doc, page);
		ctm = fz_scale(dpp, dpp);
		//    ctm=fz_concat(ctm,fz_rotate(rotation));
		bounds2 = fz_transform_rect(ctm, bounds);
		bbox = fz_round_rect(bounds2);
		printf("reading page:%d,%d,%d,%d zoom:%.2f dpi:%.0f\n",bbox.x0,bbox.y0,bbox.x1,bbox.y1,zoom,dpi);
		zoom_value = zoom;
		zoom *= shrink_factor;
		dpi *= shrink_factor;
	} while (bbox.x1 > max_page_width_pix | bbox.y1 > max_page_height_pix);
	//    ctm=fz_translate(0,-page->mediabox.y1);
	//    ctm=fz_concat(ctm,fz_scale(dpp,-dpp));
	//    ctm=fz_concat(ctm,fz_rotate(page->rotate));
	//    ctm=fz_concat(ctm,fz_rotate(0));
	//    bbox=fz_round_rect(fz_transform_rect(ctm,page->mediabox));
	//    pix=fz_new_pixmap_with_rect(colorspace,bbox);
	pix = fz_new_pixmap_with_bbox(ctx, fz_device_gray, bbox);
	fz_clear_pixmap_with_value(ctx, pix, 0xff);
	dev = fz_new_draw_device(ctx, pix);
#ifdef MUPDF_TRACE
	fz_device *tdev;
	fz_try(ctx) {
		tdev = fz_new_trace_device(ctx);
		fz_run_page(doc, page, tdev, ctm, NULL);
	}
	fz_always(ctx) {
		fz_free_device(tdev);
	}
#endif
	fz_run_page(doc, page, dev, ctm, NULL);
	fz_free_device(dev);

	if(gamma >= 0.0) {
		fz_gamma_pixmap(ctx, pix, gamma);
	}

	src = &_src;
	masterinfo = &_masterinfo;
	bmp_init(src);
	int status = bmpmupdf_pixmap_to_bmp(src, ctx, pix);
	k2pdfopt_reflow_bmp(masterinfo, src);
	bmp_free(src);

	fz_drop_pixmap(ctx, pix);
}

void k2pdfopt_djvu_reflow(ddjvu_page_t *page, ddjvu_context_t *ctx, \
		ddjvu_render_mode_t mode, ddjvu_format_t *fmt, double zoom, \
		int bb_width, int bb_height, double line_space, double word_space) {
	WILLUSBITMAP _src, *src;
	ddjvu_rect_t prect;
	ddjvu_rect_t rrect;
	int i, iw, ih, idpi, status;

	dst_userwidth  = bb_width; // dst_width is adjusted in adjust_params_init
	dst_userheight = bb_height;
	vertical_line_spacing = line_space;
	word_spacing = word_space;

	double dpi = 250*zoom;

	while (!ddjvu_page_decoding_done(page))
			handle(1, ctx);

	iw = ddjvu_page_get_width(page);
	ih = ddjvu_page_get_height(page);
	idpi = ddjvu_page_get_resolution(page);
	prect.x = prect.y = 0;
	do {
		prect.w = iw * dpi / idpi;
		prect.h = ih * dpi / idpi;
		printf("reading page:%d,%d,%d,%d dpi:%.0f\n",prect.x,prect.y,prect.w,prect.h,dpi);
		zoom_value = zoom;
		zoom *= shrink_factor;
		dpi *= shrink_factor;
	} while (prect.w > max_page_width_pix | prect.h > max_page_height_pix);
	rrect = prect;

	src = &_src;
	masterinfo = &_masterinfo;
	bmp_init(src);

	src->width = prect.w = iw * dpi / idpi;
	src->height = prect.h = ih * dpi / idpi;
	src->bpp = 8;
	rrect = prect;
	bmp_alloc(src);
	if (src->bpp == 8) {
		int ii;
		for (ii = 0; ii < 256; ii++)
		src->red[ii] = src->blue[ii] = src->green[ii] = ii;
	}

	ddjvu_format_set_row_order(fmt, 1);

	status = ddjvu_page_render(page, mode, &prect, &rrect, fmt,
			bmp_bytewidth(src), (char *) src->data);

	k2pdfopt_reflow_bmp(masterinfo, src);
	bmp_free(src);
}

void k2pdfopt_rfbmp_size(int *width, int *height) {
	*width = master_bmp_width;
	*height = master_bmp_height;
}

void k2pdfopt_rfbmp_ptr(unsigned char** bmp_ptr_ptr) {
	*bmp_ptr_ptr = masterinfo->bmp.data;
}

void k2pdfopt_rfbmp_zoom(double *zoom) {
	*zoom = zoom_value;
}

/* ansi.c */
#define MAXSIZE 8000

static int ansi_on=1;
static char ansi_buffer[MAXSIZE];

int avprintf(FILE *f, char *fmt, va_list args)

{
	int status;
	{
		if (!ansi_on) {
			status = vsprintf(ansi_buffer, fmt, args);
			ansi_parse(f, ansi_buffer);
		} else
			status = vfprintf(f, fmt, args);
	}
	return (status);
}

int aprintf(char *fmt, ...)

{
	va_list args;
	int status;

	va_start(args, fmt);
	status = avprintf(stdout, fmt, args);
	va_end(args);
	return (status);
}

/*
 ** Ensure that max_region_width_inches will be > MIN_REGION_WIDTH_INCHES
 **
 ** Should only be called once, after all params are set.
 **
 */
void adjust_params_init(void)

{
	if (dst_landscape) {
		dst_width = dst_userheight;
		dst_height = dst_userwidth;
	} else {
		dst_width = dst_userwidth;
		dst_height = dst_userheight;
	}
	if (dst_mar < 0.)
		dst_mar = 0.02;
	if (dst_martop < 0.)
		dst_martop = dst_mar;
	if (dst_marbot < 0.)
		dst_marbot = dst_mar;
	if (dst_marleft < 0.)
		dst_marleft = dst_mar;
	if (dst_marright < 0.)
		dst_marright = dst_mar;
	if ((double) dst_width / dst_dpi - dst_marleft
			- dst_marright< MIN_REGION_WIDTH_INCHES) {
		int olddpi;
		olddpi = dst_dpi;
		dst_dpi = (int) ((double) dst_width
				/ (MIN_REGION_WIDTH_INCHES + dst_marleft + dst_marright));
		aprintf(
				TTEXT_BOLD2 "Output DPI of %d is too large.  Reduced to %d." TTEXT_NORMAL "\n\n",
				olddpi, dst_dpi);
	}
}

void set_region_widths(void)

{
	max_region_width_inches = display_width_inches = (double) dst_width
			/ dst_dpi;
	max_region_width_inches -= (dst_marleft + dst_marright);
	/* This is ensured by adjust_dst_dpi() as of v1.17 */
	/*
	 if (max_region_width_inches < MIN_REGION_WIDTH_INCHES)
	 max_region_width_inches = MIN_REGION_WIDTH_INCHES;
	 */
}

/*
 ** Process full source page bitmap into rectangular regions and add
 ** to the destination bitmap.  Start by looking for columns.
 **
 ** level = recursion level.  First call = 1, then 2, ...
 **
 */
void bmpregion_multicolumn_add(BMPREGION *region, MASTERINFO *masterinfo,
		int level, PAGEINFO *pageinfo, int colgap0_pixels)

{
	static char *funcname = "bmpregion_multicolumn_add";
	int *row_black_count;
	int r2, rh, r0, cgr, maxlevel;
	BMPREGION *srcregion, _srcregion;
	BMPREGION *newregion, _newregion;
	BMPREGION *pageregion;
	double minh;
	int ipr, npr, na;
	int *colcount, *rowcount;

	willus_dmem_alloc_warn(1, (void **) &colcount,
			sizeof(int) * (region->c2 + 1), funcname, 10);
	willus_dmem_alloc_warn(2, (void **) &rowcount,
			sizeof(int) * (region->r2 + 1), funcname, 10);
	maxlevel = max_columns / 2;
	if (debug)
		printf("@bmpregion_multicolumn_add (%d,%d) - (%d,%d) lev=%d\n",
				region->c1, region->r1, region->c2, region->r2, level);
	newregion = &_newregion;
	(*newregion) = (*region);
	/* Establish colcount, rowcount arrays */
	bmpregion_trim_margins(newregion, colcount, rowcount, 0xf);
	(*newregion) = (*region);
	srcregion = &_srcregion;
	(*srcregion) = (*region);
	/* How many page regions do we need? */
	minh = min_column_height_inches;
	if (minh < .01)
		minh = .1;
	na = (srcregion->r2 - srcregion->r1 + 1) / src_dpi / minh;
	if (na < 1)
		na = 1;
	na += 16;
	/* Allocate page regions */
	willus_dmem_alloc_warn(3, (void **) &pageregion, sizeof(BMPREGION) * na,
			funcname, 10);
#ifdef COMMENT
	mindr=src_dpi*.045; /* src->height/250; */
	if (mindr<1)
	mindr=1;
#endif
//    white=250;
//    for (i=0;i<src->width;i++)
//        colcount[i]=0;
	if (debug)
		bmpregion_row_histogram(region);

	/*
	 ** Store information about which rows are mostly clear for future
	 ** processing (saves processing time).
	 */
	willus_dmem_alloc_warn(4, (void **) &row_black_count,
			region->bmp8->height * sizeof(int), funcname, 10);
	for (cgr = 0, r0 = 0; r0 < region->bmp8->height; r0++) {
		row_black_count[r0] = bmpregion_row_black_count(region, r0);
		if (row_black_count[r0] == 0)
			cgr++;
		/*
		 int dr;
		 dr=mindr;
		 if (r0+dr>region->bmp8->height)
		 dr=region->bmp8->height-r0;
		 if ((row_is_clear[r0]=bmpregion_row_mostly_white(region,r0,dr))!=0)
		 cgr++;
		 */
// printf("row_is_clear[%d]=%d\n",r0,row_is_clear[r0]);
	}
	if (verbose)
		printf("%d clear rows.\n", cgr);

	if (max_columns == 1) {
		pageregion[0] = (*srcregion);
		/* Set c1 negative to indicate full span */
		pageregion[0].c1 = -1 - pageregion[0].c1;
		npr = 1;
	} else
		/* Find all column dividers in source region and store sequentially in pageregion[] array */
		for (npr = 0, rh = 0; srcregion->r1 <= srcregion->r2; srcregion->r1 +=
				rh) {
			static char *ierr =
					TTEXT_WARN "\n\aInternal error--not enough allocated regions.\n"
					"Please inform the developer at willus.com.\n\n" TTEXT_NORMAL;
			if (npr >= na - 3) {
				aprintf("%s", ierr);
				break;
			}
			rh = bmpregion_find_multicolumn_divider(srcregion, row_black_count,
					pageregion, &npr, colcount, rowcount);
			if (verbose)
				printf("rh=%d/%d\n", rh, region->r2 - region->r1 + 1);
		}

	/* Process page regions by column */
	if (debug)
		printf("Page regions:  %d\n", npr);
	r2 = -1;
	for (ipr = 0; ipr < npr;) {
		int r20, jpr, colnum, colgap_pixels;

		for (colnum = 1; colnum <= 2; colnum++) {
			if (debug) {
				printf("ipr = %d of %d...\n", ipr, npr);
				printf("COLUMN %d...\n", colnum);
			}
			r20 = r2;
			for (jpr = ipr; jpr < npr; jpr += 2) {
				/* If we get to a page region that spans the entire source, stop */
				if (pageregion[jpr].c1 < 0)
					break;
				/* See if we should suspend this column and start displaying the next one */
				if (jpr > ipr) {
					double cpdiff, cdiv1, cdiv2, rowgap1_in, rowgap2_in;

					if (column_offset_max < 0.)
						break;
					/* Did column divider move too much? */
					cdiv1 = (pageregion[jpr].c2 + pageregion[jpr + 1].c1) / 2.;
					cdiv2 = (pageregion[jpr - 2].c2 + pageregion[jpr - 1].c1)
							/ 2.;
					cpdiff = fabs(
							(double) (cdiv1 - cdiv2)
									/ (srcregion->c2 - srcregion->c1 + 1));
					if (cpdiff > column_offset_max)
						break;
					/* Is gap between this column region and next column region too big? */
					rowgap1_in = (double) (pageregion[jpr].r1
							- pageregion[jpr - 2].r2) / src_dpi;
					rowgap2_in = (double) (pageregion[jpr + 1].r1
							- pageregion[jpr - 1].r2) / src_dpi;
					if (rowgap1_in > 0.28 && rowgap2_in > 0.28)
						break;
				}
				(*newregion) = pageregion[
						src_left_to_right ?
								jpr + colnum - 1 : jpr + (2 - colnum)];
				/* Preserve vertical gap between this region and last region */
				if (r20 >= 0 && newregion->r1 - r20 >= 0)
					colgap_pixels = newregion->r1 - r20;
				else
					colgap_pixels = colgap0_pixels;
				if (level < maxlevel)
					bmpregion_multicolumn_add(newregion, masterinfo, level + 1,
							pageinfo, colgap_pixels);
				else {
					bmpregion_vertically_break(newregion, masterinfo, text_wrap,
							fit_columns ? -2.0 : -1.0, colcount, rowcount,
							pageinfo, colgap_pixels, 2 * level);
				}
				r20 = newregion->r2;
			}
			if (r20 > r2)
				r2 = r20;
			if (jpr == ipr)
				break;
		}
		if (jpr < npr && pageregion[jpr].c1 < 0) {
			if (debug)
				printf("SINGLE COLUMN REGION...\n");
			(*newregion) = pageregion[jpr];
			newregion->c1 = -1 - newregion->c1;
			/* dst_add_gap_src_pixels("Col level",masterinfo,newregion->r1-r2); */
			colgap_pixels = newregion->r1 - r2;
			bmpregion_vertically_break(newregion, masterinfo, text_wrap,
					(fit_columns && (level > 1)) ? -2.0 : -1.0, colcount,
					rowcount, pageinfo, colgap_pixels, level);
			r2 = newregion->r2;
			jpr++;
		}
		ipr = jpr;
	}
	willus_dmem_free(4, (double **) &row_black_count, funcname);
	willus_dmem_free(3, (double **) &pageregion, funcname);
	willus_dmem_free(2, (double **) &rowcount, funcname);
	willus_dmem_free(1, (double **) &colcount, funcname);
}

static void fit_column_to_screen(double column_width_inches)

{
	double text_width_pixels, lm_pixels, rm_pixels, tm_pixels, bm_pixels;

	if (!column_fitted) {
		dpi_org = dst_dpi;
		lm_org = dst_marleft;
		rm_org = dst_marright;
		tm_org = dst_martop;
		bm_org = dst_marbot;
	}
	text_width_pixels = max_region_width_inches * dst_dpi;
	lm_pixels = dst_marleft * dst_dpi;
	rm_pixels = dst_marright * dst_dpi;
	tm_pixels = dst_martop * dst_dpi;
	bm_pixels = dst_marbot * dst_dpi;
	dst_dpi = text_width_pixels / column_width_inches;
	dst_marleft = lm_pixels / dst_dpi;
	dst_marright = rm_pixels / dst_dpi;
	dst_martop = tm_pixels / dst_dpi;
	dst_marbot = bm_pixels / dst_dpi;
	set_region_widths();
	column_fitted = 1;
}

static void restore_output_dpi(void)

{
	if (column_fitted) {
		dst_dpi = dpi_org;
		dst_marleft = lm_org;
		dst_marright = rm_org;
		dst_martop = tm_org;
		dst_marbot = bm_org;
		set_region_widths();
	}
	column_fitted = 0;
}

void adjust_contrast(WILLUSBITMAP *src, WILLUSBITMAP *srcgrey, int *white)

{
	int i, j, tries, wc, tc, hist[256];
	double contrast, rat0;
	WILLUSBITMAP *dst, _dst;

	if (debug && verbose)
		printf("\nAt adjust_contrast.\n");
	if ((*white) <= 0)
		(*white) = 192;
	/* If contrast_max negative, use it as fixed contrast adjustment. */
	if (contrast_max < 0.) {
		bmp_contrast_adjust(srcgrey, srcgrey, -contrast_max);
		if (dst_color && fabs(contrast_max + 1.0) > 1e-4)
			bmp_contrast_adjust(src, src, -contrast_max);
		return;
	}
	dst = &_dst;
	bmp_init(dst);
	wc = 0; /* Avoid compiler warning */
	tc = srcgrey->width * srcgrey->height;
	rat0 = 0.5; /* Avoid compiler warning */
	for (contrast = 1.0, tries = 0; contrast < contrast_max + .01; tries++) {
		if (fabs(contrast - 1.0) > 1e-4)
			bmp_contrast_adjust(dst, srcgrey, contrast);
		else
			bmp_copy(dst, srcgrey);
		/*Get bitmap histogram */
		for (i = 0; i < 256; i++)
			hist[i] = 0;
		for (j = 0; j < dst->height; j++) {
			unsigned char *p;
			p = bmp_rowptr_from_top(dst, j);
			for (i = 0; i < dst->width; i++, p++)
				hist[p[0]]++;
		}
		if (tries == 0) {
			int h1;
			for (h1 = 0, j = (*white); j < 256; j++)
				h1 += hist[j];
			rat0 = (double) h1 / tc;
			if (debug && verbose)
				printf("    rat0 = rat[%d-255]=%.4f\n", (*white), rat0);
		}

		/* Find white ratio */
		/*
		 for (wc=hist[254],j=253;j>=252;j--)
		 if (hist[j]>wc1)
		 wc1=hist[j];
		 */
		for (wc = 0, j = 252; j <= 255; j++)
			wc += hist[j];
		/*
		 if ((double)wc/tc >= rat0*0.7 && (double)hist[255]/wc > 0.995)
		 break;
		 */
		if (debug && verbose)
			printf("    %2d. Contrast=%7.2f, rat[252-255]/rat0=%.4f\n",
					tries + 1, contrast, (double) wc / tc / rat0);
		if ((double) wc / tc >= rat0 * 0.94)
			break;
		contrast *= 1.05;
	}
	if (debug)
		printf("Contrast=%7.2f, rat[252-255]/rat0=%.4f\n", contrast,
				(double) wc / tc / rat0);
	/*
	 bmp_write(dst,"outc.png",stdout,100);
	 wfile_written_info("outc.png",stdout);
	 exit(10);
	 */
	bmp_copy(srcgrey, dst);
	/* Maybe don't adjust the contrast for the color bitmap? */
	if (dst_color && fabs(contrast - 1.0) > 1e-4)
		bmp_contrast_adjust(src, src, contrast);
	bmp_free(dst);
}

static int bmpregion_row_black_count(BMPREGION *region, int r0)

{
	unsigned char *p;
	int i, nc, c;

	p = bmp_rowptr_from_top(region->bmp8, r0) + region->c1;
	nc = region->c2 - region->c1 + 1;
	for (c = i = 0; i < nc; i++, p++)
		if (p[0] < region->bgcolor)
			c++;
	return (c);
}

/*
 ** Returns height of region found and divider position in (*divider_column).
 ** (*divider_column) is absolute position on source bitmap.
 **
 */
static int bmpregion_find_multicolumn_divider(BMPREGION *region,
		int *row_black_count, BMPREGION *pageregion, int *npr, int *colcount,
		int *rowcount)

{
	int itop, i, dm, middle, divider_column, min_height_pixels, mhp2,
			min_col_gap_pixels;
	BMPREGION _newregion, *newregion, column[2];
	BREAKINFO *breakinfo, _breakinfo;
	int *rowmin, *rowmax;
	static char *funcname = "bmpregion_find_multicolumn_divider";

	if (debug)
		printf("@bmpregion_find_multicolumn_divider(%d,%d)-(%d,%d)\n",
				region->c1, region->r1, region->c2, region->r2);
	breakinfo = &_breakinfo;
	breakinfo->textrow = NULL;
	breakinfo_alloc(101, breakinfo, region->r2 - region->r1 + 1);
	bmpregion_find_vertical_breaks(region, breakinfo, colcount, rowcount,
			column_row_gap_height_in);
	/*
	 {
	 printf("region (%d,%d)-(%d,%d) has %d breaks:\n",region->c1,region->r1,region->c2,region->r2,breakinfo->n);
	 for (i=0;i<breakinfo->n;i++)
	 printf("    Rows %d - %d\n",breakinfo->textrow[i].r1,breakinfo->textrow[i].r2);
	 }
	 */
	newregion = &_newregion;
	(*newregion) = (*region);
	min_height_pixels = min_column_height_inches * src_dpi; /* src->height/15; */
	mhp2 = min_height_pixels - 1;
	if (mhp2 < 0)
		mhp2 = 0;
	dm = 1 + (region->c2 - region->c1 + 1) * column_gap_range / 2.;
	middle = (region->c2 - region->c1 + 1) / 2;
	min_col_gap_pixels = (int) (min_column_gap_inches * src_dpi + .5);
	if (verbose) {
		printf("(dm=%d, width=%d, min_gap=%d)\n", dm,
				region->c2 - region->c1 + 1, min_col_gap_pixels);
		printf("Checking regions (r1=%d, r2=%d, minrh=%d)..", region->r1,
				region->r2, min_height_pixels);
		fflush(stdout);
	}
	breakinfo_sort_by_row_position(breakinfo);
	willus_dmem_alloc_warn(5, (void **) &rowmin,
			(region->c2 + 10) * 2 * sizeof(int), funcname, 10);
	rowmax = &rowmin[region->c2 + 10];
	for (i = 0; i < region->c2 + 2; i++) {
		rowmin[i] = region->r2 + 2;
		rowmax[i] = -1;
	}

	/* Start with top-most and bottom-most regions, look for column dividers */
	for (itop = 0;
			itop < breakinfo->n
					&& breakinfo->textrow[itop].r1
							< region->r2 + 1 - min_height_pixels; itop++) {
		int ibottom;

		for (ibottom = breakinfo->n - 1;
				ibottom >= itop
						&& breakinfo->textrow[ibottom].r2
								- breakinfo->textrow[itop].r1
								>= min_height_pixels; ibottom--) {
			/*
			 ** Look for vertical shaft of clear space that clearly demarcates
			 ** two columns
			 */
			for (i = 0; i < dm; i++) {
				int foundgap, ii, c1, c2, iiopt, status;

				newregion->c1 = region->c1 + middle - i;
				/* If we've effectively already checked this shaft, move on */
				if (itop >= rowmin[newregion->c1]
						&& ibottom <= rowmax[newregion->c1])
					continue;
				newregion->c2 = newregion->c1 + min_col_gap_pixels - 1;
				newregion->r1 = breakinfo->textrow[itop].r1;
				newregion->r2 = breakinfo->textrow[ibottom].r2;
				foundgap = bmpregion_is_clear(newregion, row_black_count,
						gtc_in);
				if (!foundgap && i > 0) {
					newregion->c1 = region->c1 + middle + i;
					newregion->c2 = newregion->c1 + min_col_gap_pixels - 1;
					foundgap = bmpregion_is_clear(newregion, row_black_count,
							gtc_in);
				}
				if (!foundgap)
					continue;
				/* Found a gap, but look for a better gap nearby */
				c1 = newregion->c1;
				c2 = newregion->c2;
				for (iiopt = 0, ii = -min_col_gap_pixels;
						ii <= min_col_gap_pixels; ii++) {
					int newgap;
					newregion->c1 = c1 + ii;
					newregion->c2 = c2 + ii;
					newgap = bmpregion_is_clear(newregion, row_black_count,
							gtc_in);
					if (newgap > 0 && newgap < foundgap) {
						iiopt = ii;
						foundgap = newgap;
						if (newgap == 1)
							break;
					}
				}
				newregion->c1 = c1 + iiopt;
				/* If we've effectively already checked this shaft, move on */
				if (itop >= rowmin[newregion->c1]
						&& ibottom <= rowmax[newregion->c1])
					continue;
				newregion->c2 = c2 + iiopt;
				divider_column = newregion->c1 + min_col_gap_pixels / 2;
				status = bmpregion_column_height_and_gap_test(column, region,
						breakinfo->textrow[itop].r1,
						breakinfo->textrow[ibottom].r2, divider_column,
						colcount, rowcount);
				/* If fails column height or gap test, mark as bad */
				if (status) {
					if (itop < rowmin[newregion->c1])
						rowmin[newregion->c1] = itop;
					if (ibottom > rowmax[newregion->c1])
						rowmax[newregion->c1] = ibottom;
				}
				/* If right column too short, stop looking */
				if (status & 2)
					break;
				if (!status) {
					int colheight;

					/* printf("    GOT COLUMN DIVIDER AT x=%d.\n",(*divider_column)); */
					if (verbose) {
						printf("\n    GOOD REGION: col gap=(%d,%d) - (%d,%d)\n"
								"                 r1=%d, r2=%d\n",
								newregion->c1, newregion->r1, newregion->c2,
								newregion->r2, breakinfo->textrow[itop].r1,
								breakinfo->textrow[ibottom].r2);
					}
					if (itop > 0) {
						/* add 1-column region */
						pageregion[(*npr)] = (*region);
						pageregion[(*npr)].r2 = breakinfo->textrow[itop - 1].r2;
						if (pageregion[(*npr)].r2
								> pageregion[(*npr)].bmp8->height - 1)
							pageregion[(*npr)].r2 =
									pageregion[(*npr)].bmp8->height - 1;
						bmpregion_trim_margins(&pageregion[(*npr)], colcount,
								rowcount, 0xf);
						/* Special flag to indicate full-width region */
						pageregion[(*npr)].c1 = -1 - pageregion[(*npr)].c1;
						(*npr) = (*npr) + 1;
					}
					pageregion[(*npr)] = column[0];
					(*npr) = (*npr) + 1;
					pageregion[(*npr)] = column[1];
					(*npr) = (*npr) + 1;
					colheight = breakinfo->textrow[ibottom].r2 - region->r1 + 1;
					breakinfo_free(101, breakinfo);
					/*
					 printf("Returning %d divider column = %d - %d\n",region->r2-region->r1+1,newregion->c1,newregion->c2);
					 */
					return (colheight);
				}
			}
		}
	}
	if (verbose)
		printf("NO GOOD REGION FOUND.\n");
	pageregion[(*npr)] = (*region);
	bmpregion_trim_margins(&pageregion[(*npr)], colcount, rowcount, 0xf);
	/* Special flag to indicate full-width region */
	pageregion[(*npr)].c1 = -1 - pageregion[(*npr)].c1;
	(*npr) = (*npr) + 1;
	/* (*divider_column)=region->c2+1; */
	willus_dmem_free(5, (double **) &rowmin, funcname);
	breakinfo_free(101, breakinfo);
	/*
	 printf("Returning %d\n",region->r2-region->r1+1);
	 */
	return (region->r2 - region->r1 + 1);
}

/*
 ** 1 = column 1 too short
 ** 2 = column 2 too short
 ** 3 = both too short
 ** 0 = both okay
 ** Both columns must pass height requirement.
 **
 ** Also, if gap between columns > max_column_gap_inches, fails test. (8-31-12)
 **
 */
static int bmpregion_column_height_and_gap_test(BMPREGION *column,
		BMPREGION *region, int r1, int r2, int cmid, int *colcount,
		int *rowcount)

{
	int min_height_pixels, status;

	status = 0;
	min_height_pixels = min_column_height_inches * src_dpi;
	column[0] = (*region);
	column[0].r1 = r1;
	column[0].r2 = r2;
	column[0].c2 = cmid - 1;
	bmpregion_trim_margins(&column[0], colcount, rowcount, 0xf);
	/*
	 printf("    COL1:  pix=%d (%d - %d)\n",newregion->r2-newregion->r1+1,newregion->r1,newregion->r2);
	 */
	if (column[0].r2 - column[0].r1 + 1 < min_height_pixels)
		status |= 1;
	column[1] = (*region);
	column[1].r1 = r1;
	column[1].r2 = r2;
	column[1].c1 = cmid;
	column[1].c2 = region->c2;
	bmpregion_trim_margins(&column[1], colcount, rowcount, 0xf);
	/*
	 printf("    COL2:  pix=%d (%d - %d)\n",newregion->r2-newregion->r1+1,newregion->r1,newregion->r2);
	 */
	if (column[1].r2 - column[1].r1 + 1 < min_height_pixels)
		status |= 2;
	/* Make sure gap between columns is not too large */
	if (max_column_gap_inches >= 0.
			&& column[1].c1 - column[0].c2 - 1
					> max_column_gap_inches * src_dpi)
		status |= 4;
	return (status);
}

/*
 ** Return 0 if there are dark pixels in the region.  NZ otherwise.
 */
static int bmpregion_is_clear(BMPREGION *region, int *row_black_count,
		double gt_in)

{
	int r, c, nc, pt;

	/*
	 ** row_black_count[] doesn't necessarily match up to this particular region's columns.
	 ** So if row_black_count[] == 0, the row is clear, otherwise it has to be counted.
	 ** because the columns are a subset.
	 */
	/* nr=region->r2-region->r1+1; */
	nc = region->c2 - region->c1 + 1;
	pt = (int) (gt_in * src_dpi * nc + .5);
	if (pt < 0)
		pt = 0;
	for (c = 0, r = region->r1; r <= region->r2; r++) {
		if (r < 0 || r >= region->bmp8->height)
			continue;
		if (row_black_count[r] == 0)
			continue;
		c += bmpregion_row_black_count(region, r);
		if (c > pt)
			return (0);
	}
	/*
	 printf("(%d,%d)-(%d,%d):  c=%d, pt=%d (gt_in=%g)\n",
	 region->c1,region->r1,region->c2,region->r2,c,pt,gt_in);
	 */
	return (1 + (int) 10 * c / pt);
}

static void bmpregion_row_histogram(BMPREGION *region)

{
	static char *funcname = "bmpregion_row_histogram";
	WILLUSBITMAP *src;
	FILE *out;
	static int *rowcount;
	static int *hist;
	int i, j, nn;

	willus_dmem_alloc_warn(6, (void **) &rowcount,
			(region->r2 - region->r1 + 1) * sizeof(int), funcname, 10);
	willus_dmem_alloc_warn(7, (void **) &hist,
			(region->c2 - region->c1 + 1) * sizeof(int), funcname, 10);
	src = region->bmp8;
	for (j = region->r1; j <= region->r2; j++) {
		unsigned char *p;
		p = bmp_rowptr_from_top(src, j) + region->c1;
		rowcount[j - region->r1] = 0;
		for (i = region->c1; i <= region->c2; i++, p++)
			if (p[0] < region->bgcolor)
				rowcount[j - region->r1]++;
	}
	for (i = region->c1; i <= region->c2; i++)
		hist[i - region->c1] = 0;
	for (i = region->r1; i <= region->r2; i++)
		hist[rowcount[i - region->r1]]++;
	for (i = region->c2 - region->c1 + 1; i >= 0; i--)
		if (hist[i] > 0)
			break;
	nn = i;
	out = fopen("hist.ep", "w");
	for (i = 0; i <= nn; i++)
		fprintf(out, "%5d %5d\n", i, hist[i]);
	fclose(out);
	out = fopen("rowcount.ep", "w");
	for (i = 0; i < region->r2 - region->r1 + 1; i++)
		fprintf(out, "%5d %5d\n", i, rowcount[i]);
	fclose(out);
	willus_dmem_free(7, (double **) &hist, funcname);
	willus_dmem_free(6, (double **) &rowcount, funcname);
}

/*
 ** Mark the region
 ** mark_flags & 1 :  Mark top
 ** mark_flags & 2 :  Mark bottom
 ** mark_flags & 4 :  Mark left
 ** mark_flags & 8 :  Mark right
 **
 */
static void mark_source_page(BMPREGION *region0, int caller_id, int mark_flags)

{
	static int display_order = 0;
	int i, n, nn, fontsize, r, g, b, shownum;
	char num[16];
	BMPREGION *region, _region;
	BMPREGION *clip, _clip;

	if (!show_marked_source)
		return;

	if (region0 == NULL) {
		display_order = 0;
		return;
	}

	region = &_region;
	(*region) = (*region0);

	/* Clip the region w/ignored margins */
	clip = &_clip;
	clip->bmp = region0->bmp;
	get_white_margins(clip);
	if (region->c1 < clip->c1)
		region->c1 = clip->c1;
	if (region->c2 > clip->c2)
		region->c2 = clip->c2;
	if (region->r1 < clip->r1)
		region->r1 = clip->r1;
	if (region->r2 > clip->r2)
		region->r2 = clip->r2;
	if (region->r2 <= region->r1 || region->c2 <= region->c1)
		return;

	/* printf("@mark_source_page(display_order=%d)\n",display_order); */
	if (caller_id == 1) {
		display_order++;
		shownum = 1;
		n = (int) (src_dpi / 60. + 0.5);
		if (n < 5)
			n = 5;
		r = 255;
		g = b = 0;
	} else if (caller_id == 2) {
		shownum = 0;
		n = 2;
		r = 0;
		g = 0;
		b = 255;
	} else if (caller_id == 3) {
		shownum = 0;
		n = (int) (src_dpi / 80. + 0.5);
		if (n < 4)
			n = 4;
		r = 0;
		g = 255;
		b = 0;
	} else if (caller_id == 4) {
		shownum = 0;
		n = 2;
		r = 255;
		g = 0;
		b = 255;
	} else {
		shownum = 0;
		n = 2;
		r = 140;
		g = 140;
		b = 140;
	}
	if (n < 2)
		n = 2;
	nn = (region->c2 + 1 - region->c1) / 2;
	if (n > nn)
		n = nn;
	nn = (region->r2 + 1 - region->r1) / 2;
	if (n > nn)
		n = nn;
	if (n < 1)
		n = 1;
	for (i = 0; i < n; i++) {
		int j;
		unsigned char *p;
		if (mark_flags & 1) {
			p = bmp_rowptr_from_top(region->marked, region->r1 + i)
					+ region->c1 * 3;
			for (j = region->c1; j <= region->c2; j++, p += 3) {
				p[0] = r;
				p[1] = g;
				p[2] = b;
			}
		}
		if (mark_flags & 2) {
			p = bmp_rowptr_from_top(region->marked, region->r2 - i)
					+ region->c1 * 3;
			for (j = region->c1; j <= region->c2; j++, p += 3) {
				p[0] = r;
				p[1] = g;
				p[2] = b;
			}
		}
		if (mark_flags & 16) /* rowbase */
		{
			p = bmp_rowptr_from_top(region->marked, region->rowbase - i)
					+ region->c1 * 3;
			for (j = region->c1; j <= region->c2; j++, p += 3) {
				p[0] = r;
				p[1] = g;
				p[2] = b;
			}
		}
		if (mark_flags & 4)
			for (j = region->r1; j <= region->r2; j++) {
				p = bmp_rowptr_from_top(region->marked, j)
						+ (region->c1 + i) * 3;
				p[0] = r;
				p[1] = g;
				p[2] = b;
			}
		if (mark_flags & 8)
			for (j = region->r1; j <= region->r2; j++) {
				p = bmp_rowptr_from_top(region->marked, j)
						+ (region->c2 - i) * 3;
				p[0] = r;
				p[1] = g;
				p[2] = b;
			}
	}
	if (!shownum)
		return;
	fontsize = region->c2 - region->c1 + 1;
	if (fontsize > region->r2 - region->r1 + 1)
		fontsize = region->r2 - region->r1 + 1;
	fontsize /= 2;
	if (fontsize > src_dpi)
		fontsize = src_dpi;
	if (fontsize < 5)
		return;
	fontrender_set_typeface("helvetica-bold");
	fontrender_set_fgcolor(r, g, b);
	fontrender_set_bgcolor(255, 255, 255);
	fontrender_set_pixel_size(fontsize);
	fontrender_set_justification(4);
	fontrender_set_or(1);
	sprintf(num, "%d", display_order);
	fontrender_render(region->marked, (double) (region->c1 + region->c2) / 2.,
			(double) (region->marked->height - ((region->r1 + region->r2) / 2.)),
			num, 0, NULL);
	/* printf("    done mark_source_page.\n"); */
}

/*
 ** Input:  A generic rectangular region from the source file.  It will not
 **         be checked for multiple columns, but the text may be wrapped
 **         (controlled by allow_text_wrapping input).
 **
 ** force_scale == -2 :  Use same scale for entire column--fit to device
 **
 ** This function looks for vertical gaps in the region and breaks it at
 ** the widest ones (if there are significantly wider ones).
 **
 */
static void bmpregion_vertically_break(BMPREGION *region,
		MASTERINFO *masterinfo, int allow_text_wrapping, double force_scale,
		int *colcount, int *rowcount, PAGEINFO *pageinfo, int colgap_pixels,
		int ncols)

{
	static int ncols_last = -1;
	int regcount, i, i1, biggap, revert, trim_flags, allow_vertical_breaks;
	int justification_flags, caller_id, marking_flags, rbdelta;
	// int trim_left_and_right;
	BMPREGION *bregion, _bregion;
	BREAKINFO *breakinfo, _breakinfo;
	double region_width_inches, region_height_inches;

#if (WILLUSDEBUGX & 1)
	printf("\n\n@bmpregion_vertically_break.  colgap_pixels=%d\n\n",colgap_pixels);
#endif
	trim_flags = 0xf;
	allow_vertical_breaks = 1;
	justification_flags = 0x8f; /* Don't know region justification status yet.  Use user settings. */
	rbdelta = -1;
	breakinfo = &_breakinfo;
	breakinfo->textrow = NULL;
	breakinfo_alloc(102, breakinfo, region->r2 - region->r1 + 1);
	bmpregion_find_vertical_breaks(region, breakinfo, colcount, rowcount, -1.0);
	/* Should there be a check for breakinfo->n==0 here? */
	/* Don't think it breaks anything to let it go.  -- 6-11-12 */
#if (WILLUSDEBUGX & 2)
	breakinfo_echo(breakinfo);
#endif
	breakinfo_remove_small_rows(breakinfo, 0.25, 0.5, region, colcount,
			rowcount);
#if (WILLUSDEBUGX & 2)
	breakinfo_echo(breakinfo);
#endif
	breakinfo->centered = bmpregion_is_centered(region, breakinfo, 0,
			breakinfo->n - 1, NULL);
#if (WILLUSDEBUGX & 2)
	breakinfo_echo(breakinfo);
#endif
	/*
	 newregion=&_newregion;
	 for (i=0;i<breakinfo->n;i++)
	 {
	 (*newregion)=(*region);
	 newregion->r1=breakinfo->textrow[i].r1;
	 newregion->r2=breakinfo->textrow[i].r2;
	 bmpregion_add(newregion,breakinfo,masterinfo,allow_text_wrapping,force_scale,0,1,
	 colcount,rowcount,pageinfo,0,0xf);
	 }
	 breakinfo_free(breakinfo);
	 return;
	 */
	/*
	 if (!vertical_breaks)
	 {
	 caller_id=100;
	 marking_flags=0;
	 bmpregion_add(region,breakinfo,masterinfo,allow_text_wrapping,trim_flags,
	 allow_vertical_breaks,force_scale,justification_flags,
	 caller_id,colcount,rowcount,pageinfo,marking_flags,rbdelta);
	 breakinfo_free(breakinfo);
	 return;
	 }
	 */
	/* Red, numbered region */
	mark_source_page(region, 1, 0xf);
	bregion = &_bregion;
	if (debug) {
		if (!allow_text_wrapping)
			printf(
					"@bmpregion_vertically_break (no break) (%d,%d) - (%d,%d) (scale=%g)\n",
					region->c1, region->r1, region->c2, region->r2,
					force_scale);
		else
			printf(
					"@bmpregion_vertically_break (allow break) (%d,%d) - (%d,%d) (scale=%g)\n",
					region->c1, region->r1, region->c2, region->r2,
					force_scale);
	}
	/*
	 ** Tag blank rows and columns
	 */
	if (vertical_break_threshold < 0. || breakinfo->n < 6)
		biggap = -1.;
	else {
		int gap_median;
		/*
		 int rowheight_median;

		 breakinfo_sort_by_rowheight(breakinfo);
		 rowheight_median = breakinfo->textrow[breakinfo->n/2].rowheight;
		 */
#ifdef WILLUSDEBUG
		for (i=0;i<breakinfo->n;i++)
		printf("    gap[%d]=%d\n",i,breakinfo->textrow[i].gap);
#endif
		breakinfo_sort_by_gap(breakinfo);
		gap_median = breakinfo->textrow[breakinfo->n / 2].gap;
#ifdef WILLUSDEBUG
		printf("    median=%d\n",gap_median);
#endif
		biggap = gap_median * vertical_break_threshold;
		breakinfo_sort_by_row_position(breakinfo);
	}
#ifdef WILLUSDEBUG
	printf("    biggap=%d\n",biggap);
#endif
	region_width_inches = (double) (region->c2 - region->c1 + 1) / src_dpi;
	region_height_inches = (double) (region->r2 - region->r1 + 1) / src_dpi;
	/*
	 trim_left_and_right = 1;
	 if (region_width_inches <= max_region_width_inches)
	 trim_left_and_right = 0;
	 */
	/*
	 printf("force_scale=%g, rwi = %g, rwi/mrwi = %g, rhi = %g\n",
	 force_scale,
	 region_width_inches,
	 region_width_inches / max_region_width_inches,
	 region_height_inches);
	 */
	if (force_scale < -1.5 && region_width_inches > MIN_REGION_WIDTH_INCHES
			&& region_width_inches / max_region_width_inches < 1.25
			&& region_height_inches > 0.5) {
		revert = 1;
		force_scale = -1.0;
		fit_column_to_screen(region_width_inches);
		// trim_left_and_right = 0;
		allow_text_wrapping = 0;
	} else
		revert = 0;
	/* Add the regions (broken vertically) */
	caller_id = 1;
	/*
	 if (trim_left_and_right)
	 trim_flags=0xf;
	 else
	 trim_flags=0xc;
	 */
	trim_flags = 0xf;
	for (regcount = i1 = i = 0; i1 < breakinfo->n; i++) {
		int i2;

		i2 = i < breakinfo->n ? i : breakinfo->n - 1;
		if (i >= breakinfo->n
				|| (biggap > 0. && breakinfo->textrow[i2].gap >= biggap)) {
			int j, c1, c2, nc, nowrap;
			double regwidth, ar1, rh1;

// printf("CALLER 1:  i1=%d, i2=%d (breakinfo->n=%d)\n",i1,i2,breakinfo->n);
			(*bregion) = (*region);
			bregion->r1 = breakinfo->textrow[i1].r1;
			bregion->r2 = breakinfo->textrow[i2].r2;
			c1 = breakinfo->textrow[i1].c1;
			c2 = breakinfo->textrow[i1].c2;
			nc = c2 - c1 + 1;
			if (nc <= 0)
				nc = 1;
			rh1 = (double) (breakinfo->textrow[i1].r2
					- breakinfo->textrow[i1].r1 + 1) / src_dpi;
			ar1 = (double) (breakinfo->textrow[i1].r2
					- breakinfo->textrow[i1].r1 + 1) / nc;
			for (j = i1 + 1; j <= i2; j++) {
				if (c1 > breakinfo->textrow[j].c1)
					c1 = breakinfo->textrow[j].c1;
				if (c2 < breakinfo->textrow[j].c2)
					c2 = breakinfo->textrow[j].c2;
			}
			regwidth = (double) (c2 - c1 + 1) / src_dpi;
			marking_flags = (i1 == 0 ? 0 : 1)
					| (i2 == breakinfo->n - 1 ? 0 : 2);
			/* Green */
			mark_source_page(bregion, 3, marking_flags);
			nowrap = ((regwidth <= max_region_width_inches
					&& allow_text_wrapping < 2)
					|| (ar1 > no_wrap_ar_limit
							&& rh1 > no_wrap_height_limit_inches));
			/*
			 ** If between regions, or if the next region isn't going to be
			 ** wrapped, or if the next region starts a different number of
			 ** columns than before, then "flush and gap."
			 */
			if (regcount > 0 || just_flushed_internal || nowrap
					|| (ncols_last > 0 && ncols_last != ncols)) {
				int gap;
#ifdef WILLUSDEBUG
				printf("wrapflush1\n");
#endif
				if (!just_flushed_internal)
					wrapbmp_flush(masterinfo, 0, pageinfo, 0);
				gap = regcount == 0 ?
						colgap_pixels : breakinfo->textrow[i1 - 1].gap;
				if (regcount == 0 && beginning_gap_internal > 0) {
					if (last_h5050_internal > 0) {
						if (fabs(
								1.
										- (double) breakinfo->textrow[i1].h5050
												/ last_h5050_internal) > .1)
							dst_add_gap_src_pixels("Col/Page break", masterinfo,
									colgap_pixels);
						last_h5050_internal = -1;
					}
					gap = beginning_gap_internal;
					beginning_gap_internal = -1;
				}
				dst_add_gap_src_pixels("Vert break", masterinfo, gap);
			} else {
				if (regcount == 0 && beginning_gap_internal < 0)
					beginning_gap_internal = colgap_pixels;
			}
			bmpregion_add(bregion, breakinfo, masterinfo, allow_text_wrapping,
					trim_flags, allow_vertical_breaks, force_scale,
					justification_flags, caller_id, colcount, rowcount,
					pageinfo, marking_flags, rbdelta);
			regcount++;
			i1 = i2 + 1;
		}
	}
	ncols_last = ncols;
	if (revert)
		restore_output_dpi();
	breakinfo_free(102, breakinfo);
}

/*
 **
 ** MAIN BITMAP REGION ADDING FUNCTION
 **
 ** NOTE:  This function calls itself recursively!
 **
 ** Input:  A generic rectangular region from the source file.  It will not
 **         be checked for multiple columns, but the text may be wrapped
 **         (controlled by allow_text_wrapping input).
 **
 ** First, excess margins are trimmed off of the region.
 **
 ** Then, if the resulting trimmed region is wider than the max desirable width
 ** and allow_text_wrapping is non-zero, then the
 ** bmpregion_analyze_justification_and_line_spacing() function is called.
 ** Otherwise the region is scaled to fit and added to the master set of pages.
 **
 ** justification_flags
 **     Bits 6-7:  0 = document is not fully justified
 **                1 = document is fully justified
 **                2 = don't know document justification yet
 **     Bits 4-5:  0 = Use user settings
 **                1 = fully justify
 **                2 = do not fully justify
 **     Bits 2-3:  0 = document is left justified
 **                1 = document is centered
 **                2 = document is right justified
 **                3 = don't know document justification yet
 **     Bits 0-1:  0 = left justify document
 **                1 = center document
 **                2 = right justify document
 **                3 = Use user settings
 **
 ** force_scale = -2.0 : Fit column width to display width
 ** force_scale = -1.0 : Use output dpi unless the region doesn't fit.
 **                      In that case, scale it down until it fits.
 ** force_scale > 0.0  : Scale region by force_scale.
 **
 ** mark_flags & 1 :  Mark top
 ** mark_flags & 2 :  Mark bottom
 ** mark_flags & 4 :  Mark left
 ** mark_flags & 8 :  Mark right
 **
 ** trim_flags & 0x80 :  Do NOT re-trim no matter what.
 **
 */
static void bmpregion_add(BMPREGION *region, BREAKINFO *breakinfo,
		MASTERINFO *masterinfo, int allow_text_wrapping, int trim_flags,
		int allow_vertical_breaks, double force_scale, int justification_flags,
		int caller_id, int *colcount, int *rowcount, PAGEINFO *pageinfo,
		int mark_flags, int rowbase_delta)

{
	int w, wmax, i, nc, nr, h, bpp, tall_region;
	double region_width_inches;
	WILLUSBITMAP *bmp, _bmp;
	BMPREGION *newregion, _newregion;

	newregion = &_newregion;
	(*newregion) = (*region);
#if (WILLUSDEBUGX & 1)
	printf("@bmpregion_add (%d,%d) - (%d,%d)\n",region->c1,region->r1,region->c2,region->r2);
	printf("    trimflags = %X\n",trim_flags);
#endif
	if (debug) {
		if (!allow_text_wrapping)
			printf("@bmpregion_add (no break) (%d,%d) - (%d,%d) (scale=%g)\n",
					region->c1, region->r1, region->c2, region->r2,
					force_scale);
		else
			printf(
					"@bmpregion_add (allow break) (%d,%d) - (%d,%d) (scale=%g)\n",
					region->c1, region->r1, region->c2, region->r2,
					force_scale);
	}
	/*
	 ** Tag blank rows and columns and trim the blank margins off
	 ** trimflags = 0xf for all margin trim.
	 ** trimflags = 0xc for just top and bottom margins.
	 */
	bmpregion_trim_margins(newregion, colcount, rowcount, trim_flags);
#if (WILLUSDEBUGX & 1)
	printf("    After trim:  (%d,%d) - (%d,%d)\n",newregion->c1,newregion->r1,newregion->c2,newregion->r2);
#endif
	nc = newregion->c2 - newregion->c1 + 1;
	nr = newregion->r2 - newregion->r1 + 1;
// printf("nc=%d, nr=%d\n",nc,nr);
	if (verbose) {
		printf("    row range adjusted to %d - %d\n", newregion->r1,
				newregion->r2);
		printf("    col range adjusted to %d - %d\n", newregion->c1,
				newregion->c2);
	}
	if (nc <= 5 || nr <= 1)
		return;
	region_width_inches = (double) nc / src_dpi;
// printf("regwidth = %g in\n",region_width_inches);
	/* Use untrimmed region left/right if possible */
	if (caller_id == 1 && region_width_inches <= max_region_width_inches) {
		int trimleft, trimright;
		int maxpix, dpix;

		maxpix = (int) (max_region_width_inches * src_dpi + .5);
#if (WILLUSDEBUGX & 1)
		printf("    Trimming.  C's = %4d %4d %4d %4d\n",region->c1,newregion->c1,newregion->c2,region->c2);
		printf("    maxpix = %d, regwidth = %d\n",maxpix,region->c2-region->c1+1);
#endif
		if (maxpix > (region->c2 - region->c1 + 1))
			maxpix = region->c2 - region->c1 + 1;
// printf("    maxpix = %d\n",maxpix);
		dpix = (region->c2 - region->c1 + 1 - maxpix) / 2;
// printf("    dpix = %d\n",dpix);
		trimright = region->c2 - newregion->c2;
		trimleft = newregion->c1 - region->c1;
		if (trimleft < trimright) {
			if (trimleft > dpix)
				newregion->c1 = region->c1 + dpix;
			newregion->c2 = newregion->c1 + maxpix - 1;
		} else {
			if (trimright > dpix)
				newregion->c2 = region->c2 - dpix;
			newregion->c1 = newregion->c2 - maxpix + 1;
		}
		if (newregion->c1 < region->c1)
			newregion->c1 = region->c1;
		if (newregion->c2 > region->c2)
			newregion->c2 = region->c2;
		nc = newregion->c2 - newregion->c1 + 1;
#if (WILLUSDEBUGX & 1)
		printf("    Post Trim.  C's = %4d %4d %4d %4d\n",region->c1,newregion->c1,newregion->c2,region->c2);
#endif
		region_width_inches = (double) nc / src_dpi;
	}

	/*
	 ** Try breaking the region into smaller horizontal pieces (wrap text lines)
	 */
	/*
	 printf("allow_text_wrapping=%d, region_width_inches=%g, max_region_width_inches=%g\n",
	 allow_text_wrapping,region_width_inches,max_region_width_inches);
	 */
	/* New in v1.50, if allow_text_wrapping==2, unwrap short lines. */
	if (allow_text_wrapping == 2
			|| (allow_text_wrapping == 1
					&& region_width_inches > max_region_width_inches)) {
		bmpregion_analyze_justification_and_line_spacing(newregion, breakinfo,
				masterinfo, colcount, rowcount, pageinfo, 1, force_scale);
		return;
	}

	/*
	 ** If allowed, re-submit each vertical region individually
	 */
	if (allow_vertical_breaks) {
		bmpregion_analyze_justification_and_line_spacing(newregion, breakinfo,
				masterinfo, colcount, rowcount, pageinfo, 0, force_scale);
		return;
	}

	/* AT THIS POINT, BITMAP IS NOT TO BE BROKEN UP HORIZONTALLY OR VERTICALLY */
	/* (IT CAN STILL BE FULLY JUSTIFIED IF ALLOWED.) */

	/*
	 ** Scale region to fit the destination device width and add to the master bitmap.
	 **
	 **
	 ** Start by copying source region to new bitmap
	 **
	 */
// printf("c1=%d\n",newregion->c1);
	/* Is it a figure? */
	tall_region = (double) (newregion->r2 - newregion->r1 + 1) / src_dpi
			>= dst_min_figure_height_in;
	/* Re-trim left and right? */
	if ((trim_flags & 0x80) == 0) {
		/* If tall region and figure justification turned on ... */
		if ((tall_region && dst_figure_justify >= 0)
				/* ... or if centered region ... */
				|| ((trim_flags & 3) != 3
						&& ((justification_flags & 3) == 1
								|| ((justification_flags & 3) == 3
										&& (dst_justify == 1
												|| (dst_justify < 0
														&& (justification_flags
																& 0xc) == 4)))))) {
			bmpregion_trim_margins(newregion, colcount, rowcount, 0x3);
			nc = newregion->c2 - newregion->c1 + 1;
			region_width_inches = (double) nc / src_dpi;
		}
	}
#if (WILLUSDEBUGX & 1)
	aprintf("atomic region:  " ANSI_CYAN "%.2f x %.2f in" ANSI_NORMAL " c1=%d, (%d x %d) (rbdel=%d) just=0x%02X\n",
			(double)(newregion->c2-newregion->c1+1)/src_dpi,
			(double)(newregion->r2-newregion->r1+1)/src_dpi,
			newregion->c1,
			(newregion->c2-newregion->c1+1),
			(newregion->r2-newregion->r1+1),
			rowbase_delta,justification_flags);
#endif
	/* Copy atomic region into bmp */
	bmp = &_bmp;
	bmp_init(bmp);
	bmp->width = nc;
	bmp->height = nr;
	if (dst_color)
		bmp->bpp = 24;
	else {
		bmp->bpp = 8;
		for (i = 0; i < 256; i++)
			bmp->red[i] = bmp->blue[i] = bmp->green[i] = i;
	}
	bmp_alloc(bmp);
	bpp = dst_color ? 3 : 1;
// printf("r1=%d, r2=%d\n",newregion->r1,newregion->r2);
	for (i = newregion->r1; i <= newregion->r2; i++) {
		unsigned char *psrc, *pdst;

		pdst = bmp_rowptr_from_top(bmp, i - newregion->r1);
		psrc = bmp_rowptr_from_top(dst_color ? newregion->bmp : newregion->bmp8,
				i) + bpp * newregion->c1;
		memcpy(pdst, psrc, nc * bpp);
	}
	/*
	 ** Now scale to appropriate destination size.
	 **
	 ** force_scale is used to maintain uniform scaling so that
	 ** most of the regions are scaled at the same value.
	 **
	 ** force_scale = -2.0 : Fit column width to display width
	 ** force_scale = -1.0 : Use output dpi unless the region doesn't fit.
	 **                      In that case, scale it down until it fits.
	 ** force_scale > 0.0  : Scale region by force_scale.
	 **
	 */
	/* Max viewable pixel width on device screen */
	wmax = (int) (masterinfo->bmp.width - (dst_marleft + dst_marright) * dst_dpi
			+ 0.5);
	if (force_scale > 0.)
		w = (int) (force_scale * bmp->width + 0.5);
	else {
		if (region_width_inches < max_region_width_inches)
			w = (int) (region_width_inches * dst_dpi + .5);
		else
			w = wmax;
	}
	/* Special processing for tall regions (likely figures) */
	if (tall_region && w < wmax && dst_fit_to_page != 0) {
		if (dst_fit_to_page < 0)
			w = wmax;
		else {
			w = (int) (w * (1. + (double) dst_fit_to_page / 100.) + 0.5);
			if (w > wmax)
				w = wmax;
		}
	}
	h = (int) (((double) w / bmp->width) * bmp->height + .5);

	/*
	 ** If scaled dimensions are finite, add to master bitmap.
	 */
	if (w > 0 && h > 0) {
		WILLUSBITMAP *tmp, _tmp;
		int nocr;

		last_scale_factor_internal = (double) w / bmp->width;
#ifdef HAVE_OCR
		if (dst_ocr)
		{
			nocr=(int)((double)bmp->width/w+0.5);
			if (nocr < 1)
			nocr=1;
			if (nocr > 10)
			nocr=10;
			w *= nocr;
			h *= nocr;
		}
		else
#endif
		nocr = 1;
		tmp = &_tmp;
		bmp_init(tmp);
		bmp_resample(tmp, bmp, (double) 0., (double) 0., (double) bmp->width,
				(double) bmp->height, w, h);
		bmp_free(bmp);
		/*
		 {
		 static int nn=0;
		 char filename[256];
		 sprintf(filename,"xxx%02d.png",nn++);
		 bmp_write(tmp,filename,stdout,100);
		 }
		 */
		/*
		 ** Add scaled bitmap to destination.
		 */
		/* Allocate more rows if necessary */
		while (masterinfo->rows + tmp->height / nocr > masterinfo->bmp.height)
			bmp_more_rows(&masterinfo->bmp, 1.4, 255);
		/* Check special justification for tall regions */
		if (tall_region && dst_figure_justify >= 0)
			justification_flags = dst_figure_justify;
		bmp_src_to_dst(masterinfo, tmp, justification_flags, region->bgcolor,
				nocr, (int) ((double) src_dpi * tmp->width / bmp->width + .5));
		bmp_free(tmp);
	}

	/* Store delta to base of text row (used by wrapbmp_flush()) */
	last_rowbase_internal = rowbase_delta;
	/* .05 was .072 in v1.35 */
	/* dst_add_gap(&masterinfo->bmp,&masterinfo->rows,0.05); */
	/*
	 if (revert)
	 restore_output_dpi();
	 */
}

static void dst_add_gap_src_pixels(char *caller, MASTERINFO *masterinfo,
		int pixels)

{
	double gap_inches;

	/*
	 aprintf("%s " ANSI_GREEN "dst_add" ANSI_NORMAL " %.3f in (%d pix)\n",caller,(double)pixels/src_dpi,pixels);
	 */
	if (last_scale_factor_internal < 0.)
		gap_inches = (double) pixels / src_dpi;
	else
		gap_inches = (double) pixels * last_scale_factor_internal / dst_dpi;
	gap_inches *= vertical_multiplier;
	if (gap_inches > max_vertical_gap_inches)
		gap_inches = max_vertical_gap_inches;
	dst_add_gap(masterinfo, gap_inches);
}

static void dst_add_gap(MASTERINFO *masterinfo, double inches)

{
	int n, bw;
	unsigned char *p;

	n = (int) (inches * dst_dpi + .5);
	if (n < 1)
		n = 1;
	while (masterinfo->rows + n > masterinfo->bmp.height)
		bmp_more_rows(&masterinfo->bmp, 1.4, 255);
	bw = bmp_bytewidth(&masterinfo->bmp) * n;
	p = bmp_rowptr_from_top(&masterinfo->bmp, masterinfo->rows);
	memset(p, 255, bw);
	masterinfo->rows += n;
}

/*
 **
 ** Add already-scaled source bmp to destination bmp.
 ** Source bmp may be narrower than destination--if so, it may be fully justifed.
 ** dst = destination bitmap
 ** src = source bitmap
 ** dst and src bpp must match!
 ** All rows of src are applied to masterinfo->bmp starting at row masterinfo->rows
 ** Full justification is done if requested.
 **
 */
static void bmp_src_to_dst(MASTERINFO *masterinfo, WILLUSBITMAP *src,
		int justification_flags, int whitethresh, int nocr, int dpi)

{
	WILLUSBITMAP *src1, _src1;
	WILLUSBITMAP *tmp;
#ifdef HAVE_OCR
	WILLUSBITMAP _tmp;
	OCRWORDS _words,*words;
#endif
	int dw, dw2;
	int i, srcbytespp, srcbytewidth, go_full;
	int destwidth, destx0, just;

	if (src->width <= 0 || src->height <= 0)
		return;
	/*
	 printf("@bmp_src_to_dst.  dst->bpp=%d, src->bpp=%d, src=%d x %d\n",masterinfo->bmp.bpp,src->bpp,src->width,src->height);
	 */
	/*
	 {
	 static int count=0;
	 static char filename[256];

	 printf("    @bmp_src_to_dst...\n");
	 sprintf(filename,"src%05d.png",count++);
	 bmp_write(src,filename,stdout,100);
	 }
	 */
	/*
	 if (fulljust && dst_fulljustify)
	 printf("srcbytespp=%d, srcbytewidth=%d, destwidth=%d, destx0=%d, destbytewidth=%d\n",
	 srcbytespp,srcbytewidth,destwidth,destx0,dstbytewidth);
	 */

	/* Determine what justification to use */
	/* Left? */
	if ((justification_flags & 3) == 0 /* Mandatory left just */
			|| ((justification_flags & 3) == 3 /* Use user settings */
					&& (dst_justify == 0
							|| (dst_justify < 0
									&& (justification_flags & 0xc) == 0))))
		just = 0;
	else if ((justification_flags & 3) == 2
			|| ((justification_flags & 3) == 3
					&& (dst_justify == 2
							|| (dst_justify < 0
									&& (justification_flags & 0xc) == 8))))
		just = 2;
	else
		just = 1;

	/* Full justification? */
	destwidth = (int) (masterinfo->bmp.width
			- (dst_marleft + dst_marright) * dst_dpi + .5);
	go_full = (destwidth * nocr > src->width
			&& (((justification_flags & 0x30) == 0x10)
					|| ((justification_flags & 0x30) == 0 // Use user settings
							&& (dst_fulljustify == 1
									|| (dst_fulljustify < 0
											&& (justification_flags & 0xc0)
													== 0x40)))));

	/* Put fully justified text into src1 bitmap */
	if (go_full) {
		src1 = &_src1;
		bmp_init(src1);
		bmp_fully_justify(src1, src, nocr * destwidth, whitethresh, just);
	} else
		src1 = src;

#if (WILLUSDEBUGX & 1)
	printf("@bmp_src_to_dst:  jflags=0x%02X just=%d, go_full=%d\n",justification_flags,just,go_full);
	printf("    destx0=%d, destwidth=%d, src->width=%d\n",destx0,destwidth,src->width);
#endif
#ifdef HAVE_OCR
	if (dst_ocr)
	{
		/* Run OCR on the bitmap */
		words=&_words;
		ocrwords_init(words);
		ocrwords_fill_in(words,src1,whitethresh,dpi);
		/* Scale bitmap and word positions to destination size */
		if (nocr>1)
		{
			tmp=&_tmp;
			bmp_init(tmp);
			bmp_integer_resample(tmp,src1,nocr);
			ocrwords_int_scale(words,nocr);
		}
		else
		tmp=src1;
	}
	else
#endif
	tmp = src1;
	/*
	 printf("writing...\n");
	 ocrwords_box(words,tmp);
	 bmp_write(tmp,"out.png",stdout,100);
	 exit(10);
	 */
	destx0 = (int) (dst_marleft * dst_dpi + .5);
	if (just == 0)
		dw = destx0;
	else if (just == 1)
		dw = destx0 + (destwidth - tmp->width) / 2;
	else
		dw = destx0 + destwidth - tmp->width;
	if (dw < 0)
		dw = 0;
	/* Add OCR words to destination list */
#ifdef HAVE_OCR
	if (dst_ocr)
	{
		ocrwords_offset(words,dw,masterinfo->rows);
		ocrwords_concatenate(dst_ocrwords,words);
		ocrwords_free(words);
	}
#endif

	/* Add tmp bitmap to dst */
	srcbytespp = tmp->bpp == 24 ? 3 : 1;
	srcbytewidth = tmp->width * srcbytespp;
	dw2 = masterinfo->bmp.width - tmp->width - dw;
	dw *= srcbytespp;
	dw2 *= srcbytespp;
	for (i = 0; i < tmp->height; i++, masterinfo->rows++) {
		unsigned char *pdst, *psrc;

		psrc = bmp_rowptr_from_top(tmp, i);
		pdst = bmp_rowptr_from_top(&masterinfo->bmp, masterinfo->rows);
		memset(pdst, 255, dw);
		pdst += dw;
		memcpy(pdst, psrc, srcbytewidth);
		pdst += srcbytewidth;
		memset(pdst, 255, dw2);
	}

#ifdef HAVE_OCR
	if (dst_ocr && nocr>1)
	bmp_free(tmp);
#endif
	if (go_full)
		bmp_free(src1);
}

/*
 ** Spread words out in src and put into jbmp at scaling nocr
 ** In case the text can't be expanded enough,
 **     just=0 (left justify), 1 (center), 2 (right justify)
 */
static void bmp_fully_justify(WILLUSBITMAP *jbmp, WILLUSBITMAP *src,
		int jbmpwidth, int whitethresh, int just)

{
	BMPREGION srcregion;
	BREAKINFO *colbreaks, _colbreaks;
	WILLUSBITMAP gray;
	int *gappos, *gapsize;
	int i, srcbytespp, srcbytewidth, jbmpbytewidth, newwidth, destx0, ng;
	static char *funcname = "bmp_fully_justify";

	/*
	 {
	 char filename[256];
	 count++;
	 sprintf(filename,"out%03d.png",count);
	 bmp_write(src,filename,stdout,100);
	 }
	 */
	/* Init/allocate destination bitmap */
	jbmp->width = jbmpwidth;
	jbmp->height = src->height;
	jbmp->bpp = src->bpp;
	if (jbmp->bpp == 8)
		for (i = 0; i < 256; i++)
			jbmp->red[i] = jbmp->green[i] = jbmp->blue[i] = i;
	bmp_alloc(jbmp);

	/* Find breaks in the text row */
	colbreaks = &_colbreaks;
	colbreaks->textrow = NULL;
	srcregion.bgcolor = whitethresh;
	srcregion.c1 = 0;
	srcregion.c2 = src->width - 1;
	srcregion.r1 = 0;
	srcregion.r2 = src->height - 1;
	srcbytespp = src->bpp == 24 ? 3 : 1;
	if (srcbytespp == 3) {
		srcregion.bmp = src;
		srcregion.bmp8 = &gray;
		bmp_init(srcregion.bmp8);
		bmp_convert_to_greyscale_ex(srcregion.bmp8, src);
	} else {
		srcregion.bmp = src;
		srcregion.bmp8 = src;
	}
	breakinfo_alloc(103, colbreaks, src->width);
	{
		int *colcount, *rowcount;

		colcount = rowcount = NULL;
		willus_dmem_alloc_warn(8, (void **) &colcount,
				sizeof(int) * (src->width + src->height), funcname, 10);
		rowcount = &colcount[src->width];
		bmpregion_one_row_find_breaks(&srcregion, colbreaks, colcount, rowcount,
				1);
		willus_dmem_free(8, (double **) &colcount, funcname);
	}
	if (srcbytespp == 3)
		bmp_free(srcregion.bmp8);
	ng = colbreaks->n - 1;
	gappos = NULL;
	if (ng > 0) {
		int maxsize, ms2, mingap, j;

		willus_dmem_alloc_warn(9, (void **) &gappos, (2 * sizeof(int)) * ng,
				funcname, 10);
		gapsize = &gappos[ng];
		for (i = 0; i < ng; i++) {
			gappos[i] = colbreaks->textrow[i].c2 + 1;
			gapsize[i] = colbreaks->textrow[i].gap;
		}

		/* Take only the largest group of gaps */
		for (maxsize = i = 0; i < ng; i++)
			if (maxsize < gapsize[i])
				maxsize = gapsize[i];
		mingap = srcregion.lcheight * word_spacing;
		if (mingap < 2)
			mingap = 2;
		if (maxsize > mingap)
			maxsize = mingap;
		ms2 = maxsize / 2;
		for (i = j = 0; i < ng; i++)
			if (gapsize[i] > ms2) {
				if (j != i) {
					gapsize[j] = gapsize[i];
					gappos[j] = gappos[i];
				}
				j++;
			}
		ng = j;

		/* Figure out total pixel expansion */
		newwidth = src->width * 1.25;
		if (newwidth > jbmp->width)
			newwidth = jbmp->width;
	} else
		newwidth = src->width;
	breakinfo_free(103, colbreaks);

	/* Starting column in destination bitmap */
	if (just == 1)
		destx0 = (jbmp->width - newwidth) / 2;
	else if (just == 2)
		destx0 = (jbmp->width - newwidth);
	else
		destx0 = 0;

	jbmpbytewidth = bmp_bytewidth(jbmp);
	srcbytewidth = bmp_bytewidth(src);

	/* Clear entire fully justified bitmap */
	memset(bmp_rowptr_from_top(jbmp, 0), 255, jbmpbytewidth * jbmp->height);

	/* Spread out source pieces to fully justify them */
	for (i = 0; i <= ng; i++) {
		int j, dx0, dx, sx0;
		unsigned char *pdst, *psrc;

		dx = i < ng ?
				(i > 0 ? gappos[i] - gappos[i - 1] : gappos[i] + 1) :
				(i > 0 ? src->width - (gappos[i - 1] + 1) : src->width);
		dx *= srcbytespp;
		sx0 = i == 0 ? 0 : (gappos[i - 1] + 1);
		dx0 = destx0 + sx0 + (i == 0 ? 0 : (newwidth - src->width) * i / ng);
		psrc = bmp_rowptr_from_top(src, 0) + sx0 * srcbytespp;
		pdst = bmp_rowptr_from_top(jbmp, 0) + dx0 * srcbytespp;
		for (j = 0; j < src->height; j++, pdst += jbmpbytewidth, psrc +=
				srcbytewidth)
			memcpy(pdst, psrc, dx);
	}
	if (gappos != NULL)
		willus_dmem_free(9, (double **) &gappos, funcname);
}

/*
 ** flags&1  : trim c1
 ** flags&2  : trim c2
 ** flags&4  : trim r1
 ** flags&8  : trim r2
 ** flags&16 : Find rowbase, font size, etc.
 **
 ** Row base is where row dist crosses 50% on r2 side.
 ** Font size is where row dist crosses 5% on other side (r1 side).
 ** Lowercase font size is where row dist crosses 50% on r1 side.
 **
 ** For 12 pt font:
 **     Single spacing is 14.66 pts (Calibri), 13.82 pts (Times), 13.81 pts (Arial)
 **     Size of cap letter is 7.7 pts (Calibri), 8.1 pts (Times), 8.7 pts (Arial)
 **     Size of small letter is 5.7 pts (Calibri), 5.6 pts (Times), 6.5 pts (Arial)
 ** Mean line spacing = 1.15 - 1.22 (~1.16)
 ** Mean cap height = 0.68
 ** Mean small letter height = 0.49
 **
 */
static void bmpregion_trim_margins(BMPREGION *region, int *colcount0,
		int *rowcount0, int flags)

{
	int i, j, n; /* ,r1,r2,dr1,dr2,dr,vtrim,vspace; */
	int *colcount, *rowcount;
	static char *funcname = "bmpregion_trim_margins";

	/* To detect a hyphen, we need to trim and calc text base row */
	if (flags & 32)
		flags |= 0x1f;
	if (colcount0 == NULL)
		willus_dmem_alloc_warn(10, (void **) &colcount,
				sizeof(int) * (region->c2 + 1), funcname, 10);
	else
		colcount = colcount0;
	if (rowcount0 == NULL)
		willus_dmem_alloc_warn(11, (void **) &rowcount,
				sizeof(int) * (region->r2 + 1), funcname, 10);
	else
		rowcount = rowcount0;
	n = region->c2 - region->c1 + 1;
	/*
	 printf("Trim:  reg=(%d,%d) - (%d,%d)\n",region->c1,region->r1,region->c2,region->r2);
	 if (region->c2+1 > cca || region->r2+1 > rca)
	 {
	 printf("A ha 0!\n");
	 exit(10);
	 }
	 */
	memset(colcount, 0, (region->c2 + 1) * sizeof(int));
	memset(rowcount, 0, (region->r2 + 1) * sizeof(int));
	for (j = region->r1; j <= region->r2; j++) {
		unsigned char *p;
		p = bmp_rowptr_from_top(region->bmp8, j) + region->c1;
		for (i = 0; i < n; i++, p++)
			if (p[0] < region->bgcolor) {
				rowcount[j]++;
				colcount[i + region->c1]++;
			}
	}
	/*
	 ** Trim excess margins
	 */
	if (flags & 1)
		trim_to(colcount, &region->c1, region->c2,
				src_left_to_right ? 2.0 : 4.0);
	if (flags & 2)
		trim_to(colcount, &region->c2, region->c1,
				src_left_to_right ? 4.0 : 2.0);
	if (colcount0 == NULL)
		willus_dmem_free(10, (double **) &colcount, funcname);
	if (flags & 4)
		trim_to(rowcount, &region->r1, region->r2, 4.0);
	if (flags & 8)
		trim_to(rowcount, &region->r2, region->r1, 4.0);
	if (flags & 16) {
		int maxcount, mc2, h2;
		double f;

		maxcount = 0;
		for (i = region->r1; i <= region->r2; i++)
			if (rowcount[i] > maxcount)
				maxcount = rowcount[i];
		mc2 = maxcount / 2;
		for (i = region->r2; i >= region->r1; i--)
			if (rowcount[i] > mc2)
				break;
		region->rowbase = i;
		for (i = region->r1; i <= region->r2; i++)
			if (rowcount[i] > mc2)
				break;
		region->h5050 = region->lcheight = region->rowbase - i + 1;
		mc2 = maxcount / 20;
		for (i = region->r1; i <= region->r2; i++)
			if (rowcount[i] > mc2)
				break;
		region->capheight = region->rowbase - i + 1;
		/*
		 ** Sanity check capheight and lcheight
		 */
		h2 = height2_calc(&rowcount[region->r1], region->r2 - region->r1 + 1);
#if (WILLUSDEBUGX & 8)
		if (region->c2-region->c1 > 1500)
		printf("reg %d x %d (%d,%d) - (%d,%d) h2=%d ch/h2=%g\n",region->c2-region->c1+1,region->r2-region->r1+1,region->c1,region->r1,region->c2,region->r2,h2,(double)region->capheight/h2);
#endif
		if (region->capheight < h2 * 0.75)
			region->capheight = h2;
		f = (double) region->lcheight / region->capheight;
		if (f < 0.55)
			region->lcheight = (int) (0.72 * region->capheight + .5);
		else if (f > 0.85)
			region->lcheight = (int) (0.72 * region->capheight + .5);
#if (WILLUSDEBUGX & 8)
		if (region->c2-region->c1 > 1500)
		printf("    lcheight final = %d\n",region->lcheight);
#endif
#if (WILLUSDEBUGX & 10)
		if (region->c2-region->c1 > 1500 && region->r2-region->r1 < 100)
		{
			static int append=0;
			FILE *f;
			int i;
			f=fopen("textrows.ep",append==0?"w":"a");
			append=1;
			for (i=region->r1;i<=region->r2;i++)
			fprintf(f,"%d %g\n",region->rowbase-i,(double)rowcount[i]/maxcount);
			fprintf(f,"//nc\n");
			fclose(f);
		}
#endif
	} else {
		region->h5050 = region->r2 - region->r1 + 1;
		region->capheight = 0.68 * (region->r2 - region->r1 + 1);
		region->lcheight = 0.5 * (region->r2 - region->r1 + 1);
		region->rowbase = region->r2;
	}
#if (WILLUSDEBUGX & 2)
	printf("trim:\n    reg->c1=%d, reg->c2=%d\n",region->c1,region->c2);
	printf("    reg->r1=%d, reg->r2=%d, reg->rowbase=%d\n\n",region->r1,region->r2,region->rowbase);
#endif
	if (rowcount0 == NULL)
		willus_dmem_free(11, (double **) &rowcount, funcname);
}

/*
 ** Does region end in a hyphen?  If so, fill in HYPHENINFO structure.
 */
static void bmpregion_hyphen_detect(BMPREGION *region)

{
	int i, j; /* ,r1,r2,dr1,dr2,dr,vtrim,vspace; */
	int width;
	int *r0, *r1, *r2, *r3;
	int rmin, rmax, rowbytes, nrmid, rsum;
	int cstart, cend, cdir;
	unsigned char *p;
	static char *funcname = "bmpregion_hyphen_detect";

#if (WILLUSDEBUGX & 16)
	static int count=0;
	char pngfile[256];
	FILE *out;

	count++;
	printf("@bmpregion_hyphen_detect count=%d\n",count);
	sprintf(pngfile,"word%04d.png",count);
	bmpregion_write(region,pngfile);
	sprintf(pngfile,"word%04d.txt",count);
	out=fopen(pngfile,"w");
	fprintf(out,"c1=%d, c2=%d, r1=%d, r2=%d\n",region->c1,region->c2,region->r1,region->r2);
	fprintf(out,"lcheight=%d\n",region->lcheight);
#endif

	region->hyphen.ch = -1;
	region->hyphen.c2 = -1;
	if (!k2_hyphen_detect)
		return;
	width = region->c2 - region->c1 + 1;
	if (width < 2)
		return;
	willus_dmem_alloc_warn(27, (void **) &r0, sizeof(int) * 4 * width, funcname,
			10);
	r1 = &r0[width];
	r2 = &r1[width];
	r3 = &r2[width];
	for (i = 0; i < width; i++)
		r0[i] = r1[i] = r2[i] = r3[i] = -1;
	rmin = region->rowbase - region->capheight - region->lcheight * .04;
	if (rmin < region->r1)
		rmin = region->r1;
	rmax = region->rowbase + region->lcheight * .04;
	if (rmax > region->r2)
		rmax = region->r2;
	rowbytes = bmp_bytewidth(region->bmp8);
	p = bmp_rowptr_from_top(region->bmp8, 0);
	nrmid = rsum = 0;
	if (src_left_to_right) {
		cstart = region->c2;
		cend = region->c1 - 1;
		cdir = -1;
	} else {
		cstart = region->c1;
		cend = region->c2 + 1;
		cdir = 1;
	}
#if (WILLUSDEBUGX & 16)
	fprintf(out,"   j     r0     r1     r2     r3\n");
#endif
	for (j = cstart; j != cend; j += cdir) {
		int r, rmid, dr, drmax;

// printf("j=%d\n",j);
		rmid = (rmin + rmax) / 2;
// printf("   rmid=%d\n",rmid);
		drmax = region->r2 + 1 - rmid > rmid - region->r1 + 1 ?
				region->r2 + 1 - rmid : rmid - region->r1 + 1;
		/* Find dark region closest to center line */
		for (dr = 0; dr < drmax; dr++) {
			if (rmid + dr <= region->r2
					&& p[(rmid + dr) * rowbytes + j] < region->bgcolor)
				break;
			if (rmid - dr >= region->r1
					&& p[(rmid - dr) * rowbytes + j] < region->bgcolor) {
				dr = -dr;
				break;
			}
		}
#if (WILLUSDEBUGX & 16)
		fprintf(out,"    dr=%d/%d, rmid+dr=%d, rmin=%d, rmax=%d, nrmid=%d\n",dr,drmax,rmid+dr,rmin,rmax,nrmid);
#endif
		/* No dark detected or mark is outside hyphen region? */
		/* Termination criterion #1 */
		if (dr >= drmax
				|| (nrmid > 2 && (double) nrmid / region->lcheight > .1
						&& (rmid + dr < rmin || rmid + dr > rmax))) {
			if (region->hyphen.ch >= 0 && dr >= drmax)
				continue;
			if (nrmid > 2 && (double) nrmid / region->lcheight > .35) {
				region->hyphen.ch = j - cdir;
				region->hyphen.r1 = rmin;
				region->hyphen.r2 = rmax;
			}
			if (dr < drmax) {
				region->hyphen.c2 = j;
				break;
			}
			continue;
		}
		if (region->hyphen.ch >= 0) {
			region->hyphen.c2 = j;
			break;
		}
		nrmid++;
		rmid += dr;
		/* Dark spot is outside expected hyphen area */
		/*
		 if (rmid<rmin || rmid>rmax)
		 {
		 if (nrmid>0)
		 break;
		 continue;
		 }
		 */
		for (r = rmid; r >= region->r1; r--)
			if (p[r * rowbytes + j] >= region->bgcolor)
				break;
		r1[j - region->c1] = r + 1;
		r0[j - region->c1] = -1;
		if (r >= region->r1) {
			for (; r >= region->r1; r--)
				if (p[r * rowbytes + j] < region->bgcolor)
					break;
			if (r >= region->r1)
				r0[j - region->c1] = r;
		}
		for (r = rmid; r <= region->r2; r++)
			if (p[r * rowbytes + j] >= region->bgcolor)
				break;
		r2[j - region->c1] = r - 1;
		r3[j - region->c1] = -1;
		if (r <= region->r2) {
			for (; r <= region->r2; r++)
				if (p[r * rowbytes + j] < region->bgcolor)
					break;
			if (r <= region->r2)
				r3[j - region->c1] = r;
		}
#if (WILLUSDEBUGX & 16)
		fprintf(out," %4d  %4d  %4d  %4d  %4d\n",j,r0[j-region->c1],r1[j-region->c1],r2[j-region->c1],r3[j-region->c1]);
#endif
		if (region->hyphen.c2 < 0
				&& (r0[j - region->c1] >= 0 || r3[j - region->c1] >= 0))
			region->hyphen.c2 = j;
		/* Termination criterion #2 */
		if (nrmid > 2 && (double) nrmid / region->lcheight > .35
				&& (r1[j - region->c1] > rmax || r2[j - region->c1] < rmin)) {
			region->hyphen.ch = j - cdir;
			region->hyphen.r1 = rmin;
			region->hyphen.r2 = rmax;
			if (region->hyphen.c2 < 0)
				region->hyphen.c2 = j;
			break;
		}
		// rc=(r1[j-region->c1]+r2[j-region->c1])/2;
		/* DQ possible hyphen if r1/r2 out of range */
		if (nrmid > 1) {
			/* Too far away from last values? */
			if ((double) (rmin - r1[j - region->c1]) / region->lcheight > .1
					|| (double) (r2[j - region->c1] - rmax) / region->lcheight
							> .1)
				break;
			if ((double) nrmid / region->lcheight > .1 && nrmid > 1) {
				if ((double) fabs(rmin - r1[j - region->c1]) / region->lcheight
						> .1
						|| (double) (rmax - r2[j - region->c1])
								/ region->lcheight > .1)
					break;
			}
		}
		if (nrmid == 1 || r1[j - region->c1] < rmin)
			rmin = r1[j - region->c1];
		if (nrmid == 1 || r2[j - region->c1] > rmax)
			rmax = r2[j - region->c1];
		if ((double) nrmid / region->lcheight > .1 && nrmid > 1) {
			double rmean;

			/* Can't be too thick */
			if ((double) (rmax - rmin) / region->lcheight > .55
					|| (double) (rmax - rmin) / region->lcheight < .08)
				break;
			/* Must be reasonably well centered above baseline */
			rmean = (double) (rmax + rmin) / 2;
			if ((double) (region->rowbase - rmean) / region->lcheight < 0.35
					|| (double) (region->rowbase - rmean) / region->lcheight
							> 0.85)
				break;
			if ((double) (region->rowbase - rmax) / region->lcheight < 0.2
					|| (double) (region->rowbase - rmin) / region->lcheight
							> 0.92)
				break;
		}
	}
#if (WILLUSDEBUGX & 16)
	fprintf(out,"   ch=%d, c2=%d, r1=%d, r2=%d\n",region->hyphen.ch,region->hyphen.c2,region->hyphen.r1,region->hyphen.r2);
	fclose(out);
#endif
	/* More sanity checks--better to miss a hyphen than falsely detect it. */
	if (region->hyphen.ch >= 0) {
		double ar;
		/* If it's only a hyphen, then it's probably actually a dash--don't detect it. */
		if (region->hyphen.c2 < 0)
			region->hyphen.ch = -1;
		/* Check aspect ratio */
		ar = (double) (region->hyphen.r2 - region->hyphen.r1) / nrmid;
		if (ar < 0.08 || ar > 0.75)
			region->hyphen.ch = -1;
	}
	willus_dmem_free(27, (double **) &r0, funcname);
#if (WILLUSDEBUGX & 16)
	if (region->hyphen.ch>=0)
	printf("\n\n   GOT HYPHEN.\n\n");
	printf("   Exiting bmpregion_hyphen_detect\n");
#endif
}

#if (defined(WILLUSDEBUGX) || defined(WILLUSDEBUG))
static void bmpregion_write(BMPREGION *region,char *filename)

{
	int i,bpp;
	WILLUSBITMAP *bmp,_bmp;

	bmp=&_bmp;
	bmp_init(bmp);
	bmp->width=region->c2-region->c1+1;
	bmp->height=region->r2-region->r1+1;
	bmp->bpp=region->bmp->bpp;
	bpp=bmp->bpp==8?1:3;
	bmp_alloc(bmp);
	for (i=0;i<256;i++)
	bmp->red[i]=bmp->green[i]=bmp->blue[i]=i;
	for (i=0;i<bmp->height;i++)
	{
		unsigned char *s,*d;
		s=bmp_rowptr_from_top(region->bmp,region->r1+i)+region->c1*bpp;
		d=bmp_rowptr_from_top(bmp,i);
		memcpy(d,s,bmp->width*bpp);
	}
	bmp_write(bmp,filename,stdout,97);
	bmp_free(bmp);
}
#endif

#if (WILLUSDEBUGX & 6)
static void breakinfo_echo(BREAKINFO *breakinfo)

{
	int i;
	printf("@breakinfo_echo...\n");
	for (i=0;i<breakinfo->n;i++)
	printf("    %2d.  r1=%4d, rowbase=%4d, r2=%4d, c1=%4d, c2=%4d\n",
			i+1,breakinfo->textrow[i].r1,
			breakinfo->textrow[i].rowbase,
			breakinfo->textrow[i].r2,
			breakinfo->textrow[i].c1,
			breakinfo->textrow[i].c2);
}
#endif

/*
 ** Calculate weighted height of a rectangular region.
 ** This weighted height is intended to be close to the height of
 ** a capital letter, or the height of the majority of the region.
 **
 */
static int height2_calc(int *rc, int n)

{
	int i, thresh, i1, h2;
	int *c;
	static char *funcname = "height2_calc";
#if (WILLUSDEBUGX & 8)
	int cmax;
#endif

	if (n <= 0)
		return (1);
	willus_dmem_alloc_warn(12, (void **) &c, sizeof(int) * n, funcname, 10);
	memcpy(c, rc, n * sizeof(int));
	sorti(c, n);
#if (WILLUSDEBUGX & 8)
	cmax=c[n-1];
#endif
	for (i = 0; i < n - 1 && c[i] == 0; i++)
		;
	thresh = c[(i + n) / 3];
	willus_dmem_free(12, (double **) &c, funcname);
	for (i = 0; i < n - 1; i++)
		if (rc[i] >= thresh)
			break;
	i1 = i;
	for (i = n - 1; i > i1; i--)
		if (rc[i] >= thresh)
			break;
#if (WILLUSDEBUGX & 8)
// printf("thresh = %g, i1=%d, i2=%d\n",(double)thresh/cmax,i1,i);
#endif
	h2 = i - i1 + 1; /* Guaranteed to be >=1 */
	return (h2);
}

static void trim_to(int *count, int *i1, int i2, double gaplen)

{
	int del, dcount, igaplen, clevel, dlevel, defect_start, last_defect;

	igaplen = (int) (gaplen * src_dpi / 72.);
	if (igaplen < 1)
		igaplen = 1;
	/* clevel=(int)(defect_size_pts*src_dpi/72./3.); */
	clevel = 0;
	dlevel = (int) (pow(defect_size_pts * src_dpi / 72., 2.) * PI / 4. + .5);
	del = i2 > (*i1) ? 1 : -1;
	defect_start = -1;
	last_defect = -1;
	dcount = 0;
	for (; (*i1) != i2; (*i1) = (*i1) + del) {
		if (count[(*i1)] <= clevel) {
			dcount = 0; /* Reset defect size */
			continue;
		}
		/* Mark found */
		if (dcount == 0) {
			if (defect_start >= 0)
				last_defect = defect_start;
			defect_start = (*i1);
		}
		dcount += count[(*i1)];
		if (dcount >= dlevel) {
			if (last_defect >= 0 && abs(defect_start - last_defect) <= igaplen)
				(*i1) = last_defect;
			else
				(*i1) = defect_start;
			return;
		}
	}
	if (defect_start < 0)
		return;
	if (last_defect < 0) {
		(*i1) = defect_start;
		return;
	}
	if (abs(defect_start - last_defect) <= igaplen)
		(*i1) = last_defect;
	else
		(*i1) = defect_start;
}

/*
 ** A region that needs its line spacing and justification analyzed.
 **
 ** The region may be wider than the max desirable region width.
 **
 ** Input:  breakinfo should be valid row-break information for the region.
 **
 ** Calls bmpregion_one_row_wrap_and_add() for each text row from the
 ** breakinfo structure that is within the region.
 **
 */
static void bmpregion_analyze_justification_and_line_spacing(BMPREGION *region,
		BREAKINFO *breakinfo, MASTERINFO *masterinfo, int *colcount,
		int *rowcount, PAGEINFO *pageinfo, int allow_text_wrapping,
		double force_scale)

{
	int i, i1, i2, ntr, mean_row_gap, maxgap, line_spacing, nls, nch;
	BMPREGION *newregion, _newregion;
	double *id, *c1, *c2, *ch, *lch, *ls;
	int *just, *indented, *short_line;
	double capheight, lcheight, fontsize;
	int textheight, ragged_right, src_line_spacing;
	static char *funcname = "bmpregion_analyze_justification_and_line_spacing";

#if (WILLUSDEBUGX & 1)
	printf("@bmpregion_analyze_justification_and_line_spacing");
	printf("    (%d,%d) - (%d,%d)\n",region->c1,region->r1,region->c2,region->r2);
	printf("    centering = %d\n",breakinfo->centered);
#endif
#if (WILLUSDEBUGX & 2)
	breakinfo_echo(breakinfo);
#endif

	/* Locate the vertical part indices in the breakinfo structure */
	newregion = &_newregion;
	breakinfo_sort_by_row_position(breakinfo);
	for (i = 0; i < breakinfo->n; i++) {
		TEXTROW *textrow;
		textrow = &breakinfo->textrow[i];
		if ((textrow->r1 + textrow->r2) / 2 >= region->r1)
			break;
	}
	if (i >= breakinfo->n)
		return;
	i1 = i;
	for (; i < breakinfo->n; i++) {
		TEXTROW *textrow;
		textrow = &breakinfo->textrow[i];
		if ((textrow->r1 + textrow->r2) / 2 > region->r2)
			break;
	}
	i2 = i - 1;
	if (i2 < i1)
		return;
	ntr = i2 - i1 + 1;
#if (WILLUSDEBUGX & 1)
	printf("    i1=%d, i2=%d, ntr=%d\n",i1,i2,ntr);
#endif

	willus_dmem_alloc_warn(13, (void **) &c1, sizeof(double) * 6 * ntr,
			funcname, 10);
	willus_dmem_alloc_warn(14, (void **) &just, sizeof(int) * 3 * ntr, funcname,
			10);
	c2 = &c1[ntr];
	ch = &c2[ntr];
	lch = &ch[ntr];
	ls = &lch[ntr];
	id = &ls[ntr];
	indented = &just[ntr];
	short_line = &indented[ntr];
	for (i = 0; i < ntr; i++)
		id[i] = i;

	/* Find baselines / font size */
	capheight = lcheight = 0.;
	maxgap = -1;
	for (nch = nls = 0, i = i1; i <= i2; i++) {
		TEXTROW *textrow;
		double ar, rh;
		int marking_flags;

		textrow = &breakinfo->textrow[i];
		c1[i - i1] = (double) textrow->c1;
		c2[i - i1] = (double) textrow->c2;
		if (i < i2 && maxgap < textrow->gap) {
			maxgap = textrow->gap;
			if (maxgap < 2)
				maxgap = 2;
		}
		if (textrow->c2 < textrow->c1)
			ar = 100.;
		else
			ar = (double) (textrow->r2 - textrow->r1 + 1)
					/ (double) (textrow->c2 - textrow->c1 + 1);
		rh = (double) (textrow->r2 - textrow->r1 + 1) / src_dpi;
		if (i < i2 && ar <= no_wrap_ar_limit
				&& rh <= no_wrap_height_limit_inches)
			ls[nls++] = breakinfo->textrow[i + 1].r1 - textrow->r1;
		if (ar <= no_wrap_ar_limit && rh <= no_wrap_height_limit_inches) {
			ch[nch] = textrow->capheight;
			lch[nch] = textrow->lcheight;
			nch++;
		}

		/* Mark region w/gray, mark rowbase also */
		marking_flags = (i == i1 ? 0 : 1) | (i == i2 ? 0 : 2);
		if (i < i2 || textrow->r2 - textrow->rowbase > 1)
			marking_flags |= 0x10;
		(*newregion) = (*region);
		newregion->r1 = textrow->r1;
		newregion->r2 = textrow->r2;
		newregion->c1 = textrow->c1;
		newregion->c2 = textrow->c2;
		newregion->rowbase = textrow->rowbase;
		mark_source_page(newregion, 5, marking_flags);
#if (WILLUSDEBUGX & 1)
		printf("   Row %2d: (%4d,%4d) - (%4d,%4d) rowbase=%4d, lch=%d, h5050=%d, rh=%d\n",i-i1+1,textrow->c1,textrow->r1,textrow->c2,textrow->r2,textrow->rowbase,textrow->lcheight,textrow->h5050,textrow->rowheight);
#endif
	}
	wrapbmp_set_maxgap(maxgap);
	if (nch < 1)
		capheight = lcheight = 2; // Err on the side of too small
	else {
		capheight = median_val(ch, nch);
		lcheight = median_val(lch, nch);
	}
// printf("capheight = %g, lcheight = %g\n",capheight,lcheight);
	bmpregion_is_centered(region, breakinfo, i1, i2, &textheight);
	/*
	 ** For 12 pt font:
	 **     Single spacing is 14.66 pts (Calibri), 13.82 pts (Times), 13.81 pts (Arial)
	 **     Size of cap letter is 7.7 pts (Calibri), 8.1 pts (Times), 8.7 pts (Arial)
	 **     Size of small letter is 5.7 pts (Calibri), 5.6 pts (Times), 6.5 pts (Arial)
	 ** Mean line spacing = 1.15 - 1.22 (~1.16)
	 ** Mean cap height = 0.68
	 ** Mean small letter height = 0.49
	 */
	fontsize = (capheight + lcheight) / 1.17;
// printf("font size = %g pts.\n",(fontsize/src_dpi)*72.);
	/*
	 ** Set line spacing for this region
	 */
	if (nls > 0)
		src_line_spacing = median_val(ls, nls);
	else
		src_line_spacing = fontsize * 1.2;
	if (vertical_line_spacing < 0
			&& src_line_spacing
					<= fabs(vertical_line_spacing) * fontsize * 1.16)
		line_spacing = src_line_spacing;
	else
		line_spacing = fabs(vertical_line_spacing) * fontsize * 1.16;
#if (WILLUSDEBUGX & 1)
	printf("   font size = %.2f pts = %d pixels\n",(fontsize/src_dpi)*72.,(int)(fontsize+.5));
	printf("   src_line_spacing = %d, line_spacing = %d\n",src_line_spacing,line_spacing);
#endif
	/*
	 if (ntr==1)
	 rheight=  (int)((breakinfo->textrow[i1].r2 - breakinfo->textrow[i1].r1)*1.25+.5);
	 else
	 rheight = (int)((double)(breakinfo->textrow[i2].rowbase - breakinfo->textrow[i1].rowbase)/(ntr-1)+.5);
	 */
	mean_row_gap = line_spacing - textheight;
	if (mean_row_gap <= 1)
		mean_row_gap = 1;

	/* Try to figure out if we have a ragged right edge */
	if (ntr < 3)
		ragged_right = 1;
	else {
		int flushcount;

		if (src_left_to_right) {
			for (flushcount = i = 0; i < ntr; i++) {
#if (WILLUSDEBUGX & 1)
				printf("    flush_factors[%d] = %g (<.5), %g in (<.1)\n",
						i,(double)(region->c2-c2[i])/textheight,(double)(region->c2-c2[i])/src_dpi);
#endif
				if ((double) (region->c2 - c2[i]) / textheight < 0.5
						&& (double) (region->c2 - c2[i]) / src_dpi < 0.1)
					flushcount++;
			}
		} else {
			for (flushcount = i = 0; i < ntr; i++) {
#if (WILLUSDEBUGX & 1)
				printf("    flush_factors[%d] = %g (<.5), %g in (<.1)\n",
						i,(double)(c1[i]-region->c1)/textheight,(double)(c1[i]-region->c1)/src_dpi);
#endif
				if ((double) (c1[i] - region->c1) / textheight < 0.5
						&& (double) (c1[i] - region->c1) / src_dpi < 0.1)
					flushcount++;
			}
		}
		ragged_right = (flushcount <= ntr / 2);
		/*
		 if (src_left_to_right)
		 {
		 sortxyd(c2,id,ntr);
		 del = region->c2 - c2[ntr-1-ntr/3];
		 sortxyd(id,c2,ntr);
		 }
		 else
		 {
		 sortxyd(c1,id,ntr);
		 del = c1[ntr/3] - region->c1;
		 sortxyd(id,c1,ntr);
		 }
		 del /= textheight;
		 printf("del=%g\n",del);
		 ragged_right = (del > 0.5);
		 */
	}
#if (WILLUSDEBUGX & 1)
	printf("ragged_right=%d\n",ragged_right);
#endif

	/* Store justification and other info line by line */
	for (i = i1; i <= i2; i++) {
		double indent1, del;
		double i1f, ilfi, i2f, ilf, ifmin, dif;
		int centered;

		TEXTROW *textrow;
		textrow = &breakinfo->textrow[i];
		i1f = (double) (c1[i - i1] - region->c1)
				/ (region->c2 - region->c1 + 1);
		i2f = (double) (region->c2 - c2[i - i1])
				/ (region->c2 - region->c1 + 1);
		ilf = src_left_to_right ? i1f : i2f;
		ilfi = ilf * (region->c2 - region->c1 + 1) / src_dpi; /* Indent in inches */
		ifmin = i1f < i2f ? i1f : i2f;
		dif = fabs(i1f - i2f);
		if (ifmin < .01)
			ifmin = 0.01;
		if (src_left_to_right)
			indent1 = (double) (c1[i - i1] - region->c1) / textheight;
		else
			indent1 = (double) (region->c2 - c2[i - i1]) / textheight;
// printf("    row %2d:  indent1=%g\n",i-i1,indent1);
		if (!breakinfo->centered) {
			indented[i - i1] = (indent1 > 0.5 && ilfi < 1.2 && ilf < .25);
			centered =
					(!indented[i - i1] && indent1 > 1.0 && dif / ifmin < 0.5);
		} else {
			centered = (dif < 0.1 || dif / ifmin < 0.5);
			indented[i - i1] = (indent1 > 0.5 && ilfi < 1.2 && ilf < .25
					&& !centered);
		}
#if (WILLUSDEBUGX & 1)
		printf("Indent %d:  %d.  indent1=%g, ilf=%g, centered=%d\n",i-i1+1,indented[i-i1],indent1,ilf,centered);
		printf("    indent1=%g, i1f=%g, i2f=%g\n",indent1,i1f,i2f);
#endif
		if (centered)
			just[i - i1] = 4;
		else {
			/*
			 ** The .01 favors left justification over right justification in
			 ** close cases.
			 */
			if (src_left_to_right)
				just[i - i1] = indented[i - i1] || (i1f < i2f + .01) ? 0 : 8;
			else
				just[i - i1] = indented[i - i1] || (i2f < i1f + .01) ? 8 : 0;
		}
		if (src_left_to_right)
			del = (double) (region->c2 - textrow->c2);
		else
			del = (double) (textrow->c1 - region->c1);
		/* Should we keep wrapping after this line? */
		if (!ragged_right)
			short_line[i - i1] = (del / textheight > 0.5);
		else
			short_line[i - i1] = (del / (region->c2 - region->c1) > 0.25);
		/* If this row is a bigger/smaller row (font) than the next row, don't wrap. */
		if (!short_line[i - i1] && i < i2) {
			TEXTROW *t1;
			t1 = &breakinfo->textrow[i + 1];
			if ((textrow->h5050 > t1->h5050 * 1.5
					|| textrow->h5050 * 1.5 < t1->h5050)
					&& (i == 0
							|| (i > 0
									&& (textrow->rowheight > t1->rowheight * 1.5
											|| textrow->rowheight * 1.5
													< t1->rowheight))))
				short_line[i - i1] = 1;
		}
		if (!ragged_right)
			just[i - i1] |= 0x40;
#if (WILLUSDEBUGX & 1)
		printf("        just[%d]=0x%02X, shortline[%d]=%d\n",i-i1,just[i-i1],i-i1,short_line[i-i1]);
		printf("        textrow->c2=%d, region->c2=%d, del=%g, textheight=%d\n",textrow->c2,region->c2,del,textheight);
#endif
		/* If short line, it should still be fully justified if it is wrapped. */
		/*
		 if (short_line[i-i1])
		 just[i-i1] = (just[i-i1]&0xf)|0x60;
		 */
	}
	/*
	 {
	 double mean1,mean2,stdev1,stdev2;
	 array_mean(c1,ntr,&mean1,&stdev1);
	 array_mean(c2,ntr,&mean2,&stdev2);
	 printf("Mean c1, c2 = %g, %g; stddevs = %g, %g\n",mean1,mean2,stdev1,stdev2);
	 printf("textheight = %d, line_spacing = %d\n",textheight,line_spacing);
	 }
	 */
	for (i = i1; i <= i2; i++) {
		TEXTROW *textrow;
		int justflags, trimflags, centered, marking_flags, gap;

#if (WILLUSDEBUGX & 1)
		aprintf("Row " ANSI_YELLOW "%d of %d" ANSI_NORMAL " (wrap=%d)\n",i-i1+1,i2-i1+1,allow_text_wrapping);
#endif
		textrow = &breakinfo->textrow[i];
		(*newregion) = (*region);
		newregion->r1 = textrow->r1;
		newregion->r2 = textrow->r2;

		/* The |3 tells it to use the user settings for left/right/center */
		justflags = just[i - i1] | 0x3;
		centered = ((justflags & 0xc) == 4);
#if (WILLUSDEBUGX & 1)
		printf("    justflags[%d]=0x%2X, centered=%d, indented=%d\n",i-i1,justflags,centered,indented[i-i1]);
#endif
		if (allow_text_wrapping) {
			/* If this line is indented or if the justification has changed, */
			/* then start a new line.                                        */
			if (centered || indented[i - i1]
					|| (i > i1
							&& (just[i - i1] & 0xc) != (just[i - i1 - 1] & 0xc))) {
#ifdef WILLUSDEBUG
				printf("wrapflush4\n");
#endif
				wrapbmp_flush(masterinfo, 0, pageinfo, 1);
			}
#ifdef WILLUSDEBUG
			printf("    c1=%d, c2=%d\n",newregion->c1,newregion->c2);
#endif
			marking_flags = 0xc | (i == i1 ? 0 : 1) | (i == i2 ? 0 : 2);
			bmpregion_one_row_wrap_and_add(newregion, breakinfo, i, i1, i2,
					masterinfo, justflags, colcount, rowcount, pageinfo,
					line_spacing, mean_row_gap, textrow->rowbase, marking_flags,
					indented[i - i1]);
			if (centered || short_line[i - i1]) {
#ifdef WILLUSDEBUG
				printf("wrapflush5\n");
#endif
				wrapbmp_flush(masterinfo, 0, pageinfo, 2);
			}
			continue;
		}
#ifdef WILLUSDEBUG
		printf("wrapflush5a\n");
#endif
		wrapbmp_flush(masterinfo, 0, pageinfo, 1);
		/* If default justifications, ignore all analysis and just center it. */
		if (dst_justify < 0 && dst_fulljustify < 0) {
			newregion->c1 = region->c1;
			newregion->c2 = region->c2;
			justflags = 0xad; /* Force centered region, no justification */
			trimflags = 0x80;
		} else
			trimflags = 0;
		/* No wrapping:  text wrap, trim flags, vert breaks, fscale, just */
		bmpregion_add(newregion, breakinfo, masterinfo, 0, trimflags, 0,
				force_scale, justflags, 5, colcount, rowcount, pageinfo, 0,
				textrow->r2 - textrow->rowbase);
		if (vertical_line_spacing < 0) {
			int gap1;
			gap1 = line_spacing - (textrow->r2 - textrow->r1 + 1);
			if (i < i2)
				gap = textrow->gap > gap1 ? gap1 : textrow->gap;
			else {
				gap = textrow->rowheight
						- (textrow->rowbase + last_rowbase_internal);
				if (gap < mean_row_gap / 2.)
					gap = mean_row_gap;
			}
		} else {
			gap = line_spacing - (textrow->r2 - textrow->r1 + 1);
			if (gap < mean_row_gap / 2.)
				gap = mean_row_gap;
		}
		if (i < i2)
			dst_add_gap_src_pixels("No-wrap line", masterinfo, gap);
		else {
			last_h5050_internal = textrow->h5050;
			beginning_gap_internal = gap;
		}
	}
	willus_dmem_free(14, (double **) &just, funcname);
	willus_dmem_free(13, (double **) &c1, funcname);
#ifdef WILLUSDEBUG
	printf("Done wrap_and_add.\n");
#endif
}

static int bmpregion_is_centered(BMPREGION *region, BREAKINFO *breakinfo,
		int i1, int i2, int *th)

{
	int j, i, cc, n1, ntr;
	int textheight;

#if (WILLUSDEBUGX & 1)
	printf("@bmpregion_is_centered:  region=(%d,%d) - (%d,%d)\n",region->c1,region->r1,region->c2,region->r2);
	printf("    nrows = %d\n",i2-i1+1);
#endif
	ntr = i2 - i1 + 1;
	for (j = 0; j < 3; j++) {
		for (n1 = textheight = 0, i = i1; i <= i2; i++) {
			TEXTROW *textrow;
			double ar, rh;

			textrow = &breakinfo->textrow[i];
			if (textrow->c2 < textrow->c1)
				ar = 100.;
			else
				ar = (double) (textrow->r2 - textrow->r1 + 1)
						/ (double) (textrow->c2 - textrow->c1 + 1);
			rh = (double) (textrow->r2 - textrow->r1 + 1) / src_dpi;
			if (j == 2 || (j >= 1 && rh <= no_wrap_height_limit_inches)
					|| (j == 0 && rh <= no_wrap_height_limit_inches
							&& ar <= no_wrap_ar_limit)) {
				textheight += textrow->rowbase - textrow->r1 + 1;
				n1++;
			}
		}
		if (n1 > 0)
			break;
	}
	textheight = (int) ((double) textheight / n1 + .5);
	if (th != NULL) {
		(*th) = textheight;
#if (WILLUSDEBUGX & 1)
		printf("    textheight assigned (%d)\n",textheight);
#endif
		return (breakinfo->centered);
	}

	/*
	 ** Does region appear to be centered?
	 */
	for (cc = 0, i = i1; i <= i2; i++) {
		double indent1, indent2;

#if (WILLUSDEBUGX & 1)
		printf("    tr[%d].c1,c2 = %d, %d\n",i,breakinfo->textrow[i].c1,breakinfo->textrow[i].c2);
#endif
		indent1 = (double) (breakinfo->textrow[i].c1 - region->c1) / textheight;
		indent2 = (double) (region->c2 - breakinfo->textrow[i].c2) / textheight;
#if (WILLUSDEBUGX & 1)
		printf("    tr[%d].indent1,2 = %g, %g\n",i,indent1,indent2);
#endif
		/* If only one line and it spans the entire region, call it centered */
		/* Sometimes this won't be the right thing to to. */
		if (i1 == i2 && indent1 < .5 && indent2 < .5) {
#if (WILLUSDEBUGX & 1)
			printf("    One line default to bigger region (%s).\n",breakinfo->centered?"not centered":"centered");
#endif
			return (1);
		}
		if (fabs(indent1 - indent2) > 1.5) {
#if (WILLUSDEBUGX & 1)
			printf("    Region not centered.\n");
#endif
			return (0);
		}
		if (indent1 > 1.0)
			cc++;
	}
#if (WILLUSDEBUGX & 1)
	printf("Region centering:  i=%d, i2=%d, cc=%d, ntr=%d\n",i,i2,cc,ntr);
#endif
	if (cc > ntr / 2) {
#if (WILLUSDEBUGX & 1)
		printf("    Region is centered (enough obviously centered lines).\n");
#endif
		return (1);
	}
#if (WILLUSDEBUGX & 1)
	printf("    Not centered (not enough obviously centered lines).\n");
#endif
	return (0);
}

/* array.c */
/*
 **
 ** Compute mean and standard deviation
 **
 */
double array_mean(double *a, int n, double *mean, double *stddev)

{
	int i;
	double sum, avg, sum_sq;

	if (n < 1)
		return (0.);
	for (sum = sum_sq = i = 0; i < n; i++)
		sum += a[i];
	avg = sum / n;
	if (mean != NULL)
		(*mean) = avg;
	if (stddev != NULL) {
		double sum_sq;

		for (sum_sq = i = 0; i < n; i++)
			sum_sq += (a[i] - avg) * (a[i] - avg);
		(*stddev) = sqrt(sum_sq / n);
	}
	return (avg);
}

/*
 ** CAUTION:  This function re-orders the x[] array!
 */
static double median_val(double *x, int n)

{
	int i1, n1;

	if (n < 4)
		return (array_mean(x, n, NULL, NULL));
	sortd(x, n);
	if (n == 4) {
		n1 = 2;
		i1 = 1;
	} else if (n == 5) {
		n1 = 3;
		i1 = 1;
	} else {
		n1 = n / 3;
		i1 = (n - n1) / 2;
	}
	return (array_mean(&x[i1], n1, NULL, NULL));
}

/*
 **
 ** Searches the region for vertical break points and stores them into
 ** the BREAKINFO structure.
 **
 ** apsize_in = averaging aperture size in inches.  Use -1 for dynamic aperture.
 **
 */
static void bmpregion_find_vertical_breaks(BMPREGION *region,
		BREAKINFO *breakinfo, int *colcount, int *rowcount, double apsize_in)

{
	static char *funcname = "bmpregion_find_vertical_breaks";
	int nr, i, brc, brcmin, dtrc, trc, aperture, aperturemax, figrow, labelrow;
	int ntr, rhmin_pix;
	BMPREGION *newregion, _newregion;
	int *rowthresh;
	double min_fig_height, max_fig_gap, max_label_height;

	min_fig_height = dst_min_figure_height_in;
	max_fig_gap = 0.16;
	max_label_height = 0.5;
	/* Trim region and populate colcount/rowcount arrays */
	bmpregion_trim_margins(region, colcount, rowcount, 0xf);
	newregion = &_newregion;
	(*newregion) = (*region);
	if (debug)
		printf("@bmpregion_find_vertical_breaks:  (%d,%d) - (%d,%d)\n",
				region->c1, region->r1, region->c2, region->r2);
	/*
	 ** brc = consecutive blank pixel rows
	 ** trc = consecutive non-blank pixel rows
	 ** dtrc = number of non blank pixel rows since last dump
	 */
	nr = region->r2 - region->r1 + 1;
	willus_dmem_alloc_warn(15, (void **) &rowthresh, sizeof(int) * nr, funcname,
			10);
	brcmin = max_vertical_gap_inches * src_dpi;
	aperturemax = (int) (src_dpi / 72. + .5);
	if (aperturemax < 2)
		aperturemax = 2;
	aperture = (int) (src_dpi * apsize_in + .5);
	/*
	 for (i=region->r1;i<=region->r2;i++)
	 printf("rowcount[%d]=%d\n",i,rowcount[i]);
	 */
	breakinfo->rhmean_pixels = 0; // Mean text row height
	ntr = 0; // Number of text rows
	/* Fill rowthresh[] array */
	for (dtrc = 0, i = region->r1; i <= region->r2; i++) {
		int ii, i1, i2, sum, pt;

		if (apsize_in < 0.) {
			aperture = (int) (dtrc / 13.7 + .5);
			if (aperture > aperturemax)
				aperture = aperturemax;
			if (aperture < 2)
				aperture = 2;
		}
		i1 = i - aperture / 2;
		i2 = i1 + aperture - 1;
		if (i1 < region->r1)
			i1 = region->r1;
		if (i2 > region->r2)
			i2 = region->r2;
		pt = (int) ((i2 - i1 + 1) * gtr_in * src_dpi + .5); /* pixel count threshold */
		if (pt < 1)
			pt = 1;
		/* Sum over row aperture */
		for (sum = 0, ii = i1; ii <= i2; sum += rowcount[ii], ii++)
			;
		/* Does row have few enough black pixels to be considered blank? */
		if ((rowthresh[i - region->r1] = 10 * sum / pt) <= 40) {
			if (dtrc > 0) {
				breakinfo->rhmean_pixels += dtrc;
				ntr++;
			}
			dtrc = 0;
		} else
			dtrc++;
	}
	if (dtrc > 0) {
		breakinfo->rhmean_pixels += dtrc;
		ntr++;
	}
	if (ntr > 0)
		breakinfo->rhmean_pixels /= ntr;
	/*
	 printf("rhmean=%d (ntr=%d)\n",breakinfo->rhmean_pixels,ntr);
	 {
	 FILE *f;
	 static int count=0;
	 f=fopen("rthresh.ep",count==0?"w":"a");
	 count++;
	 for (i=region->r1;i<=region->r2;i++)
	 nprintf(f,"%d\n",rowthresh[i-region->r1]);
	 nprintf(f,"//nc\n");
	 fclose(f);
	 }
	 */
	/* Minimum text row height required (pixels) */
	rhmin_pix = breakinfo->rhmean_pixels / 3;
	if (rhmin_pix < .04 * src_dpi)
		rhmin_pix = .04 * src_dpi;
	if (rhmin_pix > .13 * src_dpi)
		rhmin_pix = .13 * src_dpi;
	if (rhmin_pix < 1)
		rhmin_pix = 1;
	/*
	 for (rmax=region->r2;rmax>region->r1;rmax--)
	 if (rowthresh[rmax-region->r1]>10)
	 break;
	 */
	/* Look for "row" gaps in the region so that it can be broken into */
	/* multiple "rows".                                                */
	breakinfo->n = 0;
	for (labelrow = figrow = -1, dtrc = trc = brc = 0, i = region->r1;
			i <= region->r2; i++) {
		/* Does row have few enough black pixels to be considered blank? */
		if (rowthresh[i - region->r1] <= 10) {
			trc = 0;
			brc++;
			/*
			 ** Max allowed white space between rows = max_vertical_gap_inches
			 */
			if (dtrc == 0) {
				if (brc > brcmin)
					newregion->r1++;
				continue;
			}
			/*
			 ** Big enough blank gap, so add one row / line
			 */
			if (dtrc + brc >= rhmin_pix) {
				int i0, iopt;
				double region_height_inches;
				double gap_inches;

				if (dtrc < src_dpi * 0.02)
					dtrc = src_dpi * 0.02;
				if (dtrc < 2)
					dtrc = 2;
				/* Look for more optimum point */
				for (i0 = iopt = i; i <= region->r2 && i - i0 < dtrc; i++) {
					if (rowthresh[i - region->r1]
							< rowthresh[iopt - region->r1]) {
						iopt = i;
						if (rowthresh[i - region->r1] == 0)
							break;
					}
					if (rowthresh[i - region->r1] > 100)
						break;
				}
				/* If at end of region and haven't found perfect break, stay at end */
				if (i > region->r2 && rowthresh[iopt - region->r1] > 0)
					i = region->r2;
				else
					i = iopt;
				newregion->r2 = i - 1;
				region_height_inches = (double) (newregion->r2 - newregion->r1
						+ 1) / src_dpi;

				/* Could this region be a figure? */
				if (figrow < 0 && region_height_inches >= min_fig_height) {
					/* If so, set figrow and don't process it yet. */
					figrow = newregion->r1;
					labelrow = -1;
					newregion->r1 = i;
					dtrc = trc = 0;
					brc = 1;
					continue;
				}
				/* Are we processing a figure? */
				if (figrow >= 0) {
					/* Compute most recent gap */
					if (labelrow >= 0)
						gap_inches = (double) (labelrow - newregion->r1)
								/ src_dpi;
					else
						gap_inches = -1.;
					/* If gap and region height are small enough, tack them on to the figure. */
					if (region_height_inches < max_label_height
							&& gap_inches > 0. && gap_inches < max_fig_gap)
						newregion->r1 = figrow;
					else {
						/* Not small enough--dump the previous figure. */
						newregion->r2 = newregion->r1 - 1;
						newregion->r1 = figrow;
						newregion->c1 = region->c1;
						newregion->c2 = region->c2;
						bmpregion_trim_margins(newregion, colcount, rowcount,
								0x1f);
						if (newregion->r2 > newregion->r1)
							textrow_assign_bmpregion(
									&breakinfo->textrow[breakinfo->n++],
									newregion);
						if (gap_inches > 0. && gap_inches < max_fig_gap) {
							/* This new region might be a figure--set it as the new figure */
							/* and don't dump it yet.                                      */
							figrow = newregion->r2 + 1;
							labelrow = -1;
							newregion->r1 = i;
							dtrc = trc = 0;
							brc = 1;
							continue;
						} else {
							newregion->r1 = newregion->r2 + 1;
							newregion->r2 = i - 1;
						}
					}
					/* Cancel figure processing */
					figrow = -1;
					labelrow = -1;
				}
				/*
				 if (newregion->r2 >= rmax)
				 i=newregion->r2=region->r2;
				 */
				newregion->c1 = region->c1;
				newregion->c2 = region->c2;
				bmpregion_trim_margins(newregion, colcount, rowcount, 0x1f);
				if (newregion->r2 > newregion->r1)
					textrow_assign_bmpregion(
							&breakinfo->textrow[breakinfo->n++], newregion);
				newregion->r1 = i;
				dtrc = trc = 0;
				brc = 1;
			}
		} else {
			if (figrow >= 0 && labelrow < 0)
				labelrow = i;
			dtrc++;
			trc++;
			brc = 0;
		}
	}
	newregion->r2 = region->r2;
	if (dtrc > 0 && newregion->r2 - newregion->r1 + 1 > 0) {
		/* If we were processing a figure, include it. */
		if (figrow >= 0)
			newregion->r1 = figrow;
		newregion->c1 = region->c1;
		newregion->c2 = region->c2;
		bmpregion_trim_margins(newregion, colcount, rowcount, 0x1f);
		if (newregion->r2 > newregion->r1)
			textrow_assign_bmpregion(&breakinfo->textrow[breakinfo->n++],
					newregion);
	}
	/* Compute gaps between rows and row heights */
	breakinfo_compute_row_gaps(breakinfo, region->r2);
	willus_dmem_free(15, (double **) &rowthresh, funcname);
}

static void textrow_assign_bmpregion(TEXTROW *textrow, BMPREGION *region)

{
	textrow->r1 = region->r1;
	textrow->r2 = region->r2;
	textrow->c1 = region->c1;
	textrow->c2 = region->c2;
	textrow->rowbase = region->rowbase;
	textrow->lcheight = region->lcheight;
	textrow->capheight = region->capheight;
	textrow->h5050 = region->h5050;
}

static void breakinfo_compute_row_gaps(BREAKINFO *breakinfo, int r2)

{
	int i, n;

	n = breakinfo->n;
	if (n <= 0)
		return;
	breakinfo->textrow[0].rowheight = breakinfo->textrow[0].r2
			- breakinfo->textrow[0].r1;
	for (i = 0; i < n - 1; i++)
		breakinfo->textrow[i].gap = breakinfo->textrow[i + 1].r1
				- breakinfo->textrow[i].rowbase - 1;
	/*
	 breakinfo->textrow[i].rowheight = breakinfo->textrow[i+1].r1 - breakinfo->textrow[i].r1;
	 */
	for (i = 1; i < n; i++)
		breakinfo->textrow[i].rowheight = breakinfo->textrow[i].rowbase
				- breakinfo->textrow[i - 1].rowbase;
	breakinfo->textrow[n - 1].gap = r2 - breakinfo->textrow[n - 1].rowbase;
}

static void breakinfo_compute_col_gaps(BREAKINFO *breakinfo, int c2)

{
	int i, n;

	n = breakinfo->n;
	if (n <= 0)
		return;
	for (i = 0; i < n - 1; i++) {
		breakinfo->textrow[i].gap = breakinfo->textrow[i + 1].c1
				- breakinfo->textrow[i].c2 - 1;
		breakinfo->textrow[i].rowheight = breakinfo->textrow[i + 1].c1
				- breakinfo->textrow[i].c1;
	}
	breakinfo->textrow[n - 1].gap = c2 - breakinfo->textrow[n - 1].c2;
	breakinfo->textrow[n - 1].rowheight = breakinfo->textrow[n - 1].c2
			- breakinfo->textrow[n - 1].c1;
}

static void breakinfo_remove_small_col_gaps(BREAKINFO *breakinfo, int lcheight,
		double mingap)

{
	int i, j;

	if (mingap < word_spacing)
		mingap = word_spacing;
	for (i = 0; i < breakinfo->n - 1; i++) {
		double gap;

		gap = (double) breakinfo->textrow[i].gap / lcheight;
		if (gap >= mingap)
			continue;
		breakinfo->textrow[i].c2 = breakinfo->textrow[i + 1].c2;
		breakinfo->textrow[i].gap = breakinfo->textrow[i + 1].gap;
		if (breakinfo->textrow[i + 1].r1 < breakinfo->textrow[i].r1)
			breakinfo->textrow[i].r1 = breakinfo->textrow[i + 1].r1;
		if (breakinfo->textrow[i + 1].r2 > breakinfo->textrow[i].r2)
			breakinfo->textrow[i].r2 = breakinfo->textrow[i + 1].r2;
		for (j = i + 1; j < breakinfo->n - 1; j++)
			breakinfo->textrow[j] = breakinfo->textrow[j + 1];
		breakinfo->n--;
		i--;
	}
}

static void breakinfo_remove_small_rows(BREAKINFO *breakinfo, double fracrh,
		double fracgap, BMPREGION *region, int *colcount, int *rowcount)

{
	int i, j, mg, mh, mg0, mg1;
	int c1, c2, nc;
	int *rh, *gap;
	static char *funcname = "breakinfo_remove_small_rows";

#if (WILLUSDEBUGX & 2)
	printf("@breakinfo_remove_small_rows(fracrh=%g,fracgap=%g)\n",fracrh,fracgap);
#endif
	if (breakinfo->n < 2)
		return;
	c1 = region->c1;
	c2 = region->c2;
	nc = c2 - c1 + 1;
	willus_dmem_alloc_warn(16, (void **) &rh, 2 * sizeof(int) * breakinfo->n,
			funcname, 10);
	gap = &rh[breakinfo->n];
	for (i = 0; i < breakinfo->n; i++) {
		rh[i] = breakinfo->textrow[i].r2 - breakinfo->textrow[i].r1 + 1;
		if (i < breakinfo->n - 1)
			gap[i] = breakinfo->textrow[i].gap;
	}
	sorti(rh, breakinfo->n);
	sorti(gap, breakinfo->n - 1);
	mh = rh[breakinfo->n / 2];
	mh *= fracrh;
	if (mh < 1)
		mh = 1;
	mg0 = gap[(breakinfo->n - 1) / 2];
	mg = mg0 * fracgap;
	mg1 = mg0 * 0.7;
	if (mg < 1)
		mg = 1;
#if (WILLUSDEBUGX & 2)
	printf("mh = %d x %g = %d\n",rh[breakinfo->n/2],fracrh,mh);
	printf("mg = %d x %g = %d\n",gap[breakinfo->n/2],fracgap,mg);
#endif
	for (i = 0; i < breakinfo->n; i++) {
		TEXTROW *textrow;
		int trh, gs1, gs2, g1, g2, gap_is_big, row_too_small;
		double m1, m2, row_width_inches;

		textrow = &breakinfo->textrow[i];
		trh = textrow->r2 - textrow->r1 + 1;
		if (i == 0) {
			g1 = mg0 + 1;
			gs1 = mg + 1;
		} else {
			g1 = textrow->r1 - breakinfo->textrow[i - 1].r2 - 1;
			gs1 = breakinfo->textrow[i - 1].gap;
		}
		if (i == breakinfo->n - 1) {
			g2 = mg0 + 1;
			gs2 = mg + 1;
		} else {
			g2 = breakinfo->textrow[i + 1].r1 - textrow->r2 - 1;
			gs2 = breakinfo->textrow[i].gap;
		}
#if (WILLUSDEBUGX & 2)
		printf("   rowheight[%d] = %d, mh=%d, gs1=%d, gs2=%d\n",i,trh,gs1,gs2);
#endif
		gap_is_big = (trh >= mh || (gs1 >= mg && gs2 >= mg));
		/*
		 ** Is the row width small and centered?  If so, it should probably
		 ** be attached to its nearest neighbor--it's usually a fragment of
		 ** an equation or a table/figure.
		 */
		row_width_inches = (double) (textrow->c2 - textrow->c1 + 1) / src_dpi;
		m1 = fabs(textrow->c1 - c1) / nc;
		m2 = fabs(textrow->c2 - c2) / nc;
		row_too_small = m1 > 0.1 && m2 > 0.1
				&& row_width_inches < little_piece_threshold_inches
				&& (g1 <= mg1 || g2 <= mg1);
#if (WILLUSDEBUGX & 2)
		printf("       m1=%g, m2=%g, rwi=%g, g1=%d, g2=%d, mg0=%d\n",m1,m2,row_width_inches,g1,g2,mg0);
#endif
		if (gap_is_big && !row_too_small)
			continue;
#if (WILLUSDEBUGX & 2)
		printf("   row[%d] to be combined w/next row.\n",i);
#endif
		if (row_too_small) {
			if (g1 < g2)
				i--;
		} else {
			if (gs1 < gs2)
				i--;
		}
		/*
		 printf("Removing row.  nrows=%d, rh=%d, gs1=%d, gs2=%d\n",breakinfo->n,trh,gs1,gs2);
		 printf("    mh = %d, mg = %d\n",rh[breakinfo->n/2],gap[(breakinfo->n-1)/2]);
		 */
		breakinfo->textrow[i].r2 = breakinfo->textrow[i + 1].r2;
		if (breakinfo->textrow[i + 1].c2 > breakinfo->textrow[i].c2)
			breakinfo->textrow[i].c2 = breakinfo->textrow[i + 1].c2;
		if (breakinfo->textrow[i + 1].c1 < breakinfo->textrow[i].c1)
			breakinfo->textrow[i].c1 = breakinfo->textrow[i + 1].c1;
		/* Re-compute rowbase, capheight, lcheight */
		{
			BMPREGION newregion;
			newregion = (*region);
			newregion.c1 = breakinfo->textrow[i].c1;
			newregion.c2 = breakinfo->textrow[i].c2;
			newregion.r1 = breakinfo->textrow[i].r1;
			newregion.r2 = breakinfo->textrow[i].r2;
			bmpregion_trim_margins(&newregion, colcount, rowcount, 0x1f);
			newregion.c1 = breakinfo->textrow[i].c1;
			newregion.c2 = breakinfo->textrow[i].c2;
			newregion.r1 = breakinfo->textrow[i].r1;
			newregion.r2 = breakinfo->textrow[i].r2;
			textrow_assign_bmpregion(&breakinfo->textrow[i], &newregion);
		}
		for (j = i + 1; j < breakinfo->n - 1; j++)
			breakinfo->textrow[j] = breakinfo->textrow[j + 1];
		breakinfo->n--;
		i--;
	}
	willus_dmem_free(16, (double **) &rh, funcname);
}

static void breakinfo_alloc(int index, BREAKINFO *breakinfo, int nrows)

{
	static char *funcname = "breakinfo_alloc";

	willus_dmem_alloc_warn(index, (void **) &breakinfo->textrow,
			sizeof(TEXTROW) * (nrows / 2 + 2), funcname, 10);
}

static void breakinfo_free(int index, BREAKINFO *breakinfo)

{
	static char *funcname = "breakinfo_free";

	willus_dmem_free(index, (double **) &breakinfo->textrow, funcname);
}

static void breakinfo_sort_by_gap(BREAKINFO *breakinfo)

{
	int n, top, n1;
	TEXTROW *x, x0;

	x = breakinfo->textrow;
	n = breakinfo->n;
	if (n < 2)
		return;
	top = n / 2;
	n1 = n - 1;
	while (1) {
		if (top > 0) {
			top--;
			x0 = x[top];
		} else {
			x0 = x[n1];
			x[n1] = x[0];
			n1--;
			if (!n1) {
				x[0] = x0;
				return;
			}
		}
		{
			int parent, child;

			parent = top;
			child = top * 2 + 1;
			while (child <= n1) {
				if (child < n1 && x[child].gap < x[child + 1].gap)
					child++;
				if (x0.gap < x[child].gap) {
					x[parent] = x[child];
					parent = child;
					child += (parent + 1);
				} else
					break;
			}
			x[parent] = x0;
		}
	}
}

static void breakinfo_sort_by_row_position(BREAKINFO *breakinfo)

{
	int n, top, n1;
	TEXTROW *x, x0;

	x = breakinfo->textrow;
	n = breakinfo->n;
	if (n < 2)
		return;
	top = n / 2;
	n1 = n - 1;
	while (1) {
		if (top > 0) {
			top--;
			x0 = x[top];
		} else {
			x0 = x[n1];
			x[n1] = x[0];
			n1--;
			if (!n1) {
				x[0] = x0;
				return;
			}
		}
		{
			int parent, child;

			parent = top;
			child = top * 2 + 1;
			while (child <= n1) {
				if (child < n1 && x[child].r1 < x[child + 1].r1)
					child++;
				if (x0.r1 < x[child].r1) {
					x[parent] = x[child];
					parent = child;
					child += (parent + 1);
				} else
					break;
			}
			x[parent] = x0;
		}
	}
}

/*
 ** Add a vertically-contiguous rectangular region to the destination bitmap.
 ** The rectangular region may be broken up horizontally (wrapped).
 */
static void bmpregion_one_row_find_breaks(BMPREGION *region,
		BREAKINFO *breakinfo, int *colcount, int *rowcount, int add_to_dbase)

{
	int nc, i, mingap, col0, dr, thlow, thhigh;
	int *bp;
	BMPREGION *newregion, _newregion;
	static char *funcname = "bmpregion_one_row_find_breaks";

	if (debug)
		printf("@bmpregion_one_row_find_breaks(%d,%d)-(%d,%d)\n", region->c1,
				region->r1, region->c2, region->r2);
	newregion = &_newregion;
	(*newregion) = (*region);
	bmpregion_trim_margins(newregion, colcount, rowcount, 0x1f);
	region->lcheight = newregion->lcheight;
	region->capheight = newregion->capheight;
	region->rowbase = newregion->rowbase;
	region->h5050 = newregion->h5050;
	nc = newregion->c2 - newregion->c1 + 1;
	breakinfo->n = 0;
	if (nc < 6)
		return;
	/*
	 ** Look for "space-sized" gaps, i.e. gaps that would occur between words.
	 ** Use this as pixel counting aperture.
	 */
	dr = newregion->lcheight;
	mingap = dr * word_spacing * 0.8;
	if (mingap < 2)
		mingap = 2;

	/*
	 ** Find places where there are gaps (store in bp array)
	 ** Could do this more intelligently--maybe calculate a histogram?
	 */
	willus_dmem_alloc_warn(18, (void **) &bp, sizeof(int) * nc, funcname, 10);
	for (i = 0; i < nc; i++)
		bp[i] = 0;
	if (src_left_to_right) {
		for (i = newregion->c1; i <= newregion->c2; i++) {
			int i1, i2, pt, sum, ii;
			i1 = i - mingap / 2;
			i2 = i1 + mingap - 1;
			if (i1 < newregion->c1)
				i1 = newregion->c1;
			if (i2 > newregion->c2)
				i2 = newregion->c2;
			pt = (int) ((i2 - i1 + 1) * gtw_in * src_dpi + .5);
			if (pt < 1)
				pt = 1;
			for (sum = 0, ii = i1; ii <= i2; ii++, sum += colcount[ii])
				;
			bp[i - newregion->c1] = 10 * sum / pt;
		}
	} else {
		for (i = newregion->c2; i >= newregion->c1; i--) {
			int i1, i2, pt, sum, ii;
			i1 = i - mingap / 2;
			i2 = i1 + mingap - 1;
			if (i1 < newregion->c1)
				i1 = newregion->c1;
			if (i2 > newregion->c2)
				i2 = newregion->c2;
			pt = (int) ((i2 - i1 + 1) * gtw_in * src_dpi + .5);
			if (pt < 1)
				pt = 1;
			for (sum = 0, ii = i1; ii <= i2; ii++, sum += colcount[ii])
				;
			bp[i - newregion->c1] = 10 * sum / pt;
		}
	}
#if (WILLUSDEBUGX & 4)
	if (region->r1 > 3699 && region->r1<3750)
	{
		static int a=0;
		FILE *f;
		f=fopen("outbp.ep",a==0?"w":"a");
		a++;
		fprintf(f,"/sa l \"(%d,%d)-(%d,%d) lch=%d\" 2\n",region->c1,region->r1,region->c2,region->r2,region->lcheight);
		for (i=0;i<nc;i++)
		fprintf(f,"%d\n",bp[i]);
		fprintf(f,"//nc\n");
		fclose(f);
	}
#endif
	thlow = 10;
	thhigh = 50;
	/*
	 ** Break into pieces
	 */
	for (col0 = newregion->c1; col0 <= newregion->c2; col0++) {
		int copt, c0;
		BMPREGION xregion;

		xregion = (*newregion);
		xregion.c1 = col0;
		for (; col0 <= newregion->c2; col0++)
			if (bp[col0 - newregion->c1] >= thhigh)
				break;
		if (col0 > newregion->c2)
			break;
		for (col0++; col0 <= newregion->c2; col0++)
			if (bp[col0 - newregion->c1] < thlow)
				break;
		for (copt = c0 = col0; col0 <= newregion->c2 && col0 - c0 <= dr;
				col0++) {
			if (bp[col0 - newregion->c1] < bp[copt - newregion->c1])
				copt = col0;
			if (bp[col0 - newregion->c1] > thhigh)
				break;
		}
		if (copt > newregion->c2)
			copt = newregion->c2;
		xregion.c2 = copt;
		if (xregion.c2 - xregion.c1 < 2)
			continue;
		bmpregion_trim_margins(&xregion, colcount, rowcount, 0x1f);
		textrow_assign_bmpregion(&breakinfo->textrow[breakinfo->n++], &xregion);
		col0 = copt;
		if (copt == newregion->c2)
			break;
	}
	breakinfo_compute_col_gaps(breakinfo, newregion->c2);
	willus_dmem_free(18, (double **) &bp, funcname);

	/* Remove small gaps */
	{
		double median_gap;
		word_gaps_add(add_to_dbase ? breakinfo : NULL, region->lcheight,
				&median_gap);
		breakinfo_remove_small_col_gaps(breakinfo, region->lcheight,
				median_gap / 1.9);
	}
}

/*
 ** pi = preserve indentation
 */
static void bmpregion_one_row_wrap_and_add(BMPREGION *region,
		BREAKINFO *rowbreakinfo, int index, int i1, int i2,
		MASTERINFO *masterinfo, int justflags, int *colcount, int *rowcount,
		PAGEINFO *pageinfo, int line_spacing, int mean_row_gap, int rowbase,
		int marking_flags, int pi)

{
	int nc, nr, i, i0, gappix;
	double aspect_ratio, region_height;
	BREAKINFO *colbreaks, _colbreaks;
	BMPREGION *newregion, _newregion;

#if (WILLUSDEBUGX & 4)
	printf("@bmpregion_one_row_wrap_and_add, index=%d, i1=%d, i2=%d\n",index,i1,i2);
#endif
	newregion = &_newregion;
	(*newregion) = (*region);
	bmpregion_trim_margins(newregion, colcount, rowcount, 0xf);
	nc = newregion->c2 - newregion->c1 + 1;
	nr = newregion->r2 - newregion->r1 + 1;
	if (nc < 6)
		return;
	aspect_ratio = (double) nr / nc;
	region_height = (double) nr / src_dpi;
	if (aspect_ratio > no_wrap_ar_limit
			&& region_height > no_wrap_height_limit_inches) {
		newregion->r1 = region->r1;
		newregion->r2 = region->r2;
#ifdef WILLUSDEBUG
		printf("wrapflush6\n");
#endif
		wrapbmp_flush(masterinfo, 0, pageinfo, 1);
		if (index > i1)
			dst_add_gap_src_pixels("Tall region", masterinfo,
					rowbreakinfo->textrow[index - 1].gap);
		bmpregion_add(newregion, rowbreakinfo, masterinfo, 0, 0xf, 0, -1.0, 0,
				2, colcount, rowcount, pageinfo, 0xf,
				rowbreakinfo->textrow[index].r2
						- rowbreakinfo->textrow[index].rowbase);
		if (index < i2)
			gap_override_internal = rowbreakinfo->textrow[index].gap;
		return;
	}
	colbreaks = &_colbreaks;
	colbreaks->textrow = NULL;
	breakinfo_alloc(106, colbreaks, newregion->c2 - newregion->c1 + 1);
	bmpregion_one_row_find_breaks(newregion, colbreaks, colcount, rowcount, 1);
	if (pi && colbreaks->n > 0) {
		if (src_left_to_right)
			colbreaks->textrow[0].c1 = region->c1;
		else
			colbreaks->textrow[colbreaks->n - 1].c2 = region->c2;
	}
	/*
	 hs=0.;
	 for (i=0;i<colbreaks->n;i++)
	 hs += (colbreaks->textrow[i].r2-colbreaks->textrow[i].r1);
	 hs /= colbreaks->n;
	 */
	/*
	 ** Find appropriate letter height to use for word spacing
	 */
	{
		double median_gap;
		word_gaps_add(NULL, newregion->lcheight, &median_gap);
		gappix = (int) (median_gap * newregion->lcheight + .5);
	}
#if (WILLUSDEBUGX & 4)
	printf("Before small gap removal, column breaks:\n");
	breakinfo_echo(colbreaks);
#endif
#if (WILLUSDEBUGX & 4)
	printf("After small gap removal, column breaks:\n");
	breakinfo_echo(colbreaks);
#endif
	if (show_marked_source)
		for (i = 0; i < colbreaks->n; i++) {
			BMPREGION xregion;
			xregion = (*newregion);
			xregion.c1 = colbreaks->textrow[i].c1;
			xregion.c2 = colbreaks->textrow[i].c2;
			mark_source_page(&xregion, 2, marking_flags);
		}
#if (WILLUSDEBUGX & 4)
	for (i=0;i<colbreaks->n;i++)
	printf("    colbreak[%d] = %d - %d\n",i,colbreaks->textrow[i].c1,colbreaks->textrow[i].c2);
#endif
	/* Maybe skip gaps < 0.5*median_gap or collect gap/rowheight ratios and skip small gaps */
	/* (Could be thrown off by full-justified articles where some lines have big gaps.)     */
	/* Need do call a separate function that removes these gaps. */
	for (i0 = 0; i0 < colbreaks->n;) {
		int i1, i2, toolong, rw, remaining_width_pixels;
		BMPREGION reg;

		toolong = 0; /* Avoid compiler warning */
		for (i = i0; i < colbreaks->n; i++) {
			int wordgap;

			wordgap = wrapbmp_ends_in_hyphen() ? 0 : gappix;
			i1 = src_left_to_right ? i0 : colbreaks->n - 1 - i;
			i2 = src_left_to_right ? i : colbreaks->n - 1 - i0;
			rw = (colbreaks->textrow[i2].c2 - colbreaks->textrow[i1].c1 + 1);
			remaining_width_pixels = wrapbmp_remaining();
			toolong = (rw + wordgap > remaining_width_pixels);
#if (WILLUSDEBUGX & 4)
			printf("    i1=%d, i2=%d, rw=%d, rw+gap=%d, remainder=%d, toolong=%d\n",i1,i2,rw,rw+wordgap,remaining_width_pixels,toolong);
#endif
			/*
			 ** If we're too long with just one word and there is already
			 ** stuff on the queue, then flush it and re-evaluate.
			 */
			if (i == i0 && toolong && wrapbmp_width() > 0) {
#ifdef WILLUSDEBUG
				printf("wrapflush8\n");
#endif
				wrapbmp_flush(masterinfo, 1, pageinfo, 0);
				i--;
				continue;
			}
			/*
			 ** If we're not too long and we're not done yet, add another word.
			 */
			if (i < colbreaks->n - 1 && !toolong)
				continue;
			/*
			 ** Add the regions from i0 to i (or i0 to i-1)
			 */
			break;
		}
		if (i > i0 && toolong)
			i--;
		i1 = src_left_to_right ? i0 : colbreaks->n - 1 - i;
		i2 = src_left_to_right ? i : colbreaks->n - 1 - i0;
		reg = (*newregion);
		reg.c1 = colbreaks->textrow[i1].c1;
		reg.c2 = colbreaks->textrow[i2].c2;
#if (WILLUSDEBUGX & 4)
		printf("    Adding i1=%d to i2=%d\n",i1,i2);
#endif
		/* Trim the word top/bottom */
		bmpregion_trim_margins(&reg, colcount, rowcount, 0xc);
		reg.c1 = colbreaks->textrow[i1].c1;
		reg.c2 = colbreaks->textrow[i2].c2;
		reg.lcheight = newregion->lcheight;
		reg.capheight = newregion->capheight;
		reg.rowbase = newregion->rowbase;
		reg.h5050 = newregion->h5050;
		if (reg.r1 > reg.rowbase)
			reg.r1 = reg.rowbase;
		if (reg.r2 < reg.rowbase)
			reg.r2 = reg.rowbase;
		/* Add it to the existing line queue */
		wrapbmp_add(&reg, gappix, line_spacing, rowbase, mean_row_gap,
				justflags);
		if (toolong) {
#ifdef WILLUSDEBUG
			printf("wrapflush7\n");
#endif
			wrapbmp_flush(masterinfo, 1, pageinfo, 0);
		}
		i0 = i + 1;
	}
	breakinfo_free(106, colbreaks);
}

static WILLUSBITMAP _wrapbmp, *wrapbmp;
static int wrapbmp_base;
static int wrapbmp_line_spacing;
static int wrapbmp_gap;
static int wrapbmp_bgcolor;
static int wrapbmp_just;
static int wrapbmp_rhmax;
static int wrapbmp_thmax;
static int wrapbmp_maxgap = 2;
static int wrapbmp_height_extended;
static HYPHENINFO wrapbmp_hyphen;

void wrapbmp_init(void)

{
	wrapbmp = &_wrapbmp;
	bmp_init(wrapbmp);
	wrapbmp_set_color(dst_color);
	wrapbmp->width = 0;
	wrapbmp->height = 0;
	wrapbmp_base = 0;
	wrapbmp_line_spacing = -1;
	wrapbmp_gap = -1;
	wrapbmp_bgcolor = -1;
	wrapbmp_height_extended = 0;
	wrapbmp_just = 0x8f;
	wrapbmp_rhmax = -1;
	wrapbmp_thmax = -1;
	wrapbmp_hyphen.ch = -1;
	just_flushed_internal = 0;
	beginning_gap_internal = -1;
	last_h5050_internal = -1;
}

static int wrapbmp_ends_in_hyphen(void)

{
	return (wrapbmp_hyphen.ch >= 0);
}

static void wrapbmp_set_color(int is_color)

{
	if (is_color)
		wrapbmp->bpp = 24;
	else {
		int i;

		wrapbmp->bpp = 8;
		for (i = 0; i < 256; i++)
			wrapbmp->red[i] = wrapbmp->blue[i] = wrapbmp->green[i] = i;
	}
}

static void wrapbmp_free(void)

{
	bmp_free(wrapbmp);
}

static void wrapbmp_set_maxgap(int value)

{
	wrapbmp_maxgap = value;
}

static int wrapbmp_width(void)

{
	return (wrapbmp->width);
}

static int wrapbmp_remaining(void)

{
	int maxpix, w;
	maxpix = max_region_width_inches * src_dpi;
	/* Don't include hyphen if wrapbmp ends in a hyphen */
	if (wrapbmp_hyphen.ch < 0)
		w = wrapbmp->width;
	else if (src_left_to_right)
		w = wrapbmp_hyphen.c2 + 1;
	else
		w = wrapbmp->width - wrapbmp_hyphen.c2;
	return (maxpix - w);
}

/*
 ** region = bitmap region to add to line
 ** gap = horizontal pixel gap between existing region and region being added
 ** line_spacing = desired spacing between lines of text (pixels)
 ** rbase = position of baseline in region
 ** gio = gap if over--gap above top of text if it goes over line_spacing.
 */
// static int bcount=0;
static void wrapbmp_add(BMPREGION *region, int gap, int line_spacing, int rbase,
		int gio, int just_flags)

{
	WILLUSBITMAP *tmp, _tmp;
	int i, rh, th, bw, new_base, h2, bpp, width0;
// static char filename[256];

#ifdef WILLUSDEBUG
	printf("@wrapbmp_add %d x %d (w=%d).\n",region->c2-region->c1+1,region->r2-region->r1+1,wrapbmp->width);
#endif
	bmpregion_hyphen_detect(region); /* Figure out if what we're adding ends in a hyphen */
	if (wrapbmp_ends_in_hyphen())
		gap = 0;
	wrapbmp_hyphen_erase();
	just_flushed_internal = 0; // Reset "just flushed" flag
	beginning_gap_internal = -1; // Reset top-of-page or top-of-column gap
	last_h5050_internal = -1; // Reset last row font size
	if (line_spacing > wrapbmp_line_spacing)
		wrapbmp_line_spacing = line_spacing;
	if (gio > wrapbmp_gap)
		wrapbmp_gap = gio;
	wrapbmp_bgcolor = region->bgcolor;
	wrapbmp_just = just_flags;
	/*
	 printf("    c1=%d, c2=%d, r1=%d, r2=%d\n",region->c1,region->c2,region->r1,region->r2);
	 printf("    gap=%d, line_spacing=%d, rbase=%d, gio=%d\n",gap,line_spacing,rbase,gio);
	 */
	bpp = dst_color ? 3 : 1;
	rh = rbase - region->r1 + 1;
	if (rh > wrapbmp_rhmax)
		wrapbmp_rhmax = rh;
	th = rh + (region->r2 - rbase);
	if (th > wrapbmp_thmax)
		wrapbmp_thmax = th;
	/*
	 {
	 WILLUSBITMAP *bmp,_bmp;

	 bmp=&_bmp;
	 bmp_init(bmp);
	 bmp->height=region->r2-region->r1+1;
	 bmp->width=region->c2-region->c1+1;
	 bmp->bpp=bpp*8;
	 if (bpp==1)
	 for (i=0;i<256;i++)
	 bmp->red[i]=bmp->blue[i]=bmp->green[i]=i;
	 bmp_alloc(bmp);
	 bw=bmp_bytewidth(bmp);
	 memset(bmp_rowptr_from_top(bmp,0),255,bw*bmp->height);
	 for (i=region->r1;i<=region->r2;i++)
	 {
	 unsigned char *d,*s;
	 d=bmp_rowptr_from_top(bmp,i-region->r1);
	 s=bmp_rowptr_from_top(dst_color?region->bmp:region->bmp8,i)+bpp*region->c1;
	 if (i==rbase)
	 memset(d,0,bw);
	 else
	 memcpy(d,s,bw);
	 }
	 sprintf(filename,"out%05d.png",bcount++);
	 bmp_write(bmp,filename,stdout,100);
	 bmp_free(bmp);
	 }
	 */
	if (wrapbmp->width == 0) {
		/* Put appropriate gap in */
		if (last_rowbase_internal >= 0
				&& rh < wrapbmp_line_spacing - last_rowbase_internal) {
			rh = wrapbmp_line_spacing - last_rowbase_internal;
			if (rh < 2)
				rh = 2;
			th = rh + (region->r2 - rbase);
			wrapbmp_height_extended = 0;
		} else
			wrapbmp_height_extended = (last_rowbase_internal >= 0);
		wrapbmp_base = rh - 1;
		wrapbmp->height = th;
#ifdef WILLUSDEBUG
		printf("@wrapbmp_add:  bmpheight set to %d (wls=%d, lrbi=%d)\n",wrapbmp->height,wrapbmp_line_spacing,last_rowbase_internal);
#endif
		wrapbmp->width = region->c2 - region->c1 + 1;
		bmp_alloc(wrapbmp);
		bw = bmp_bytewidth(wrapbmp);
		memset(bmp_rowptr_from_top(wrapbmp, 0), 255, bw * wrapbmp->height);
		for (i = region->r1; i <= region->r2; i++) {
			unsigned char *d, *s;
			d = bmp_rowptr_from_top(wrapbmp, wrapbmp_base + (i - rbase));
			s = bmp_rowptr_from_top(dst_color ? region->bmp : region->bmp8, i)
					+ bpp * region->c1;
			memcpy(d, s, bw);
		}
#ifdef WILLUSDEBUG
		if (wrapbmp->height<=wrapbmp_base)
		{
			printf("1. SCREEECH!\n");
			printf("wrapbmp = %d x %d, base=%d\n",wrapbmp->width,wrapbmp->height,wrapbmp_base);
			exit(10);
		}
#endif
		/* Copy hyphen info from added region */
		wrapbmp_hyphen = region->hyphen;
		if (wrapbmp_ends_in_hyphen()) {
			wrapbmp_hyphen.r1 += (wrapbmp_base - rbase);
			wrapbmp_hyphen.r2 += (wrapbmp_base - rbase);
			wrapbmp_hyphen.ch -= region->c1;
			wrapbmp_hyphen.c2 -= region->c1;
		}
		return;
	}
	width0 = wrapbmp->width; /* Starting wrapbmp width */
	tmp = &_tmp;
	bmp_init(tmp);
	bmp_copy(tmp, wrapbmp);
	tmp->width += gap + region->c2 - region->c1 + 1;
	if (rh > wrapbmp_base) {
		wrapbmp_height_extended = 1;
		new_base = rh - 1;
	} else
		new_base = wrapbmp_base;
	if (region->r2 - rbase > wrapbmp->height - 1 - wrapbmp_base)
		h2 = region->r2 - rbase;
	else
		h2 = wrapbmp->height - 1 - wrapbmp_base;
	tmp->height = new_base + h2 + 1;
	bmp_alloc(tmp);
	bw = bmp_bytewidth(tmp);
	memset(bmp_rowptr_from_top(tmp, 0), 255, bw * tmp->height);
	bw = bmp_bytewidth(wrapbmp);
	/*
	 printf("3.  wbh=%d x %d, tmp=%d x %d x %d, new_base=%d, wbbase=%d\n",wrapbmp->width,wrapbmp->height,tmp->width,tmp->height,tmp->bpp,new_base,wrapbmp_base);
	 */
	for (i = 0; i < wrapbmp->height; i++) {
		unsigned char *d, *s;
		d = bmp_rowptr_from_top(tmp, i + new_base - wrapbmp_base)
				+ (src_left_to_right ? 0 : tmp->width - 1 - wrapbmp->width)
						* bpp;
		s = bmp_rowptr_from_top(wrapbmp, i);
		memcpy(d, s, bw);
	}
	bw = bpp * (region->c2 - region->c1 + 1);
	if (region->r1 + new_base - rbase < 0
			|| region->r2 + new_base - rbase > tmp->height - 1) {
		aprintf(ANSI_YELLOW "INTERNAL ERROR--TMP NOT DIMENSIONED PROPERLY.\n");
		aprintf("(%d-%d), tmp->height=%d\n" ANSI_NORMAL,
				region->r1 + new_base - rbase, region->r2 + new_base - rbase,
				tmp->height);
		exit(10);
	}
	for (i = region->r1; i <= region->r2; i++) {
		unsigned char *d, *s;

		d = bmp_rowptr_from_top(tmp, i + new_base - rbase)
				+ (src_left_to_right ? wrapbmp->width + gap : 0) * bpp;
		s = bmp_rowptr_from_top(dst_color ? region->bmp : region->bmp8, i)
				+ bpp * region->c1;
		memcpy(d, s, bw);
	}
	bmp_copy(wrapbmp, tmp);
	bmp_free(tmp);
	/* Copy region's hyphen info */
	wrapbmp_hyphen = region->hyphen;
	if (wrapbmp_ends_in_hyphen()) {
		wrapbmp_hyphen.r1 += (new_base - rbase);
		wrapbmp_hyphen.r2 += (new_base - rbase);
		if (src_left_to_right) {
			wrapbmp_hyphen.ch += width0 + gap - region->c1;
			wrapbmp_hyphen.c2 += width0 + gap - region->c1;
		} else {
			wrapbmp_hyphen.ch -= region->c1;
			wrapbmp_hyphen.c2 -= region->c1;
		}
	}
	wrapbmp_base = new_base;
#ifdef WILLUSDEBUG
	if (wrapbmp->height<=wrapbmp_base)
	{
		printf("2. SCREEECH!\n");
		printf("wrapbmp = %d x %d, base=%d\n",wrapbmp->width,wrapbmp->height,wrapbmp_base);
		exit(10);
	}
#endif
}

static void wrapbmp_flush(MASTERINFO *masterinfo, int allow_full_justification,
		PAGEINFO *pageinfo, int use_bgi)

{
	BMPREGION region;
	WILLUSBITMAP *bmp8, _bmp8;
	int gap, just, nomss, dh;
	int *colcount, *rowcount;
	static char *funcname = "wrapbmp_flush";
// char filename[256];

	if (wrapbmp->width <= 0) {
		if (use_bgi == 1 && beginning_gap_internal > 0)
			dst_add_gap_src_pixels("wrapbmp_bgi0", masterinfo,
					beginning_gap_internal);
		beginning_gap_internal = -1;
		last_h5050_internal = -1;
		if (use_bgi)
			just_flushed_internal = 1;
		return;
	}
#ifdef WILLUSDEBUG
	printf("@wrapbmp_flush()\n");
#endif
	/*
	 {
	 char filename[256];
	 int i;
	 static int bcount=0;
	 for (i=0;i<wrapbmp->height;i++)
	 {
	 unsigned char *p;
	 int j;
	 p=bmp_rowptr_from_top(wrapbmp,i);
	 for (j=0;j<wrapbmp->width;j++)
	 if (p[j]>240)
	 p[j]=192;
	 }
	 sprintf(filename,"out%05d.png",bcount++);
	 bmp_write(wrapbmp,filename,stdout,100);
	 }
	 */
	colcount = rowcount = NULL;
	willus_dmem_alloc_warn(19, (void **) &colcount,
			(wrapbmp->width + 16) * sizeof(int), funcname, 10);
	willus_dmem_alloc_warn(20, (void **) &rowcount,
			(wrapbmp->height + 16) * sizeof(int), funcname, 10);
	region.c1 = 0;
	region.c2 = wrapbmp->width - 1;
	region.r1 = 0;
	region.r2 = wrapbmp->height - 1;
	region.rowbase = wrapbmp_base;
	region.bmp = wrapbmp;
	region.bgcolor = wrapbmp_bgcolor;
#ifdef WILLUSDEBUG
	printf("Bitmap is %d x %d (baseline=%d)\n",wrapbmp->width,wrapbmp->height,wrapbmp_base);
#endif

	/* Sanity check on row spacing -- don't let it be too large. */
	nomss = wrapbmp_rhmax * 1.7; /* Nominal single-spaced height for this row */
	if (last_rowbase_internal < 0)
		dh = 0;
	else {
		dh = (int) (wrapbmp_line_spacing - last_rowbase_internal
				- 1.2 * fabs(vertical_line_spacing) * nomss + .5);
		if (vertical_line_spacing < 0.) {
			int dh1;
			if (wrapbmp_maxgap > 0)
				dh1 = region.rowbase + 1 - wrapbmp_rhmax - wrapbmp_maxgap;
			else
				dh1 = (int) (wrapbmp_line_spacing - last_rowbase_internal
						- 1.2 * nomss + .5);
			if (dh1 > dh)
				dh = dh1;
		}
	}
	if (dh > 0) {
#ifdef WILLUSDEBUG
		aprintf(ANSI_YELLOW "dh > 0 = %d" ANSI_NORMAL "\n",dh);
		printf("    wrapbmp_line_spacing=%d\n",wrapbmp_line_spacing);
		printf("    nomss = %d\n",nomss);
		printf("    vls = %g\n",vertical_line_spacing);
		printf("    lrbi=%d\n",last_rowbase_internal);
		printf("    wrapbmp_maxgap=%d\n",wrapbmp_maxgap);
		printf("    wrapbmp_rhmax=%d\n",wrapbmp_rhmax);
#endif
		region.r1 = dh;
		/*
		 if (dh>200)
		 {
		 bmp_write(wrapbmp,"out.png",stdout,100);
		 exit(10);
		 }
		 */
	}
	if (wrapbmp->bpp == 24) {
		bmp8 = &_bmp8;
		bmp_init(bmp8);
		bmp_convert_to_greyscale_ex(bmp8, wrapbmp);
		region.bmp8 = bmp8;
	} else
		region.bmp8 = wrapbmp;
	if (gap_override_internal > 0) {
		region.r1 = wrapbmp_base - wrapbmp_rhmax + 1;
		if (region.r1 < 0)
			region.r1 = 0;
		if (region.r1 > wrapbmp_base)
			region.r1 = wrapbmp_base;
		gap = gap_override_internal;
		gap_override_internal = -1;
	} else {
		if (wrapbmp_height_extended)
			gap = wrapbmp_gap;
		else
			gap = 0;
	}
#ifdef WILLUSDEBUG
	printf("wf:  gap=%d\n",gap);
#endif
	if (gap > 0)
		dst_add_gap_src_pixels("wrapbmp", masterinfo, gap);
	if (!allow_full_justification)
		just = (wrapbmp_just & 0xcf) | 0x20;
	else
		just = wrapbmp_just;
	bmpregion_add(&region, NULL, masterinfo, 0, 0, 0, -1.0, just, 2, colcount,
			rowcount, pageinfo, 0xf, wrapbmp->height - 1 - wrapbmp_base);
	if (wrapbmp->bpp == 24)
		bmp_free(bmp8);
	willus_dmem_free(20, (double **) &rowcount, funcname);
	willus_dmem_free(19, (double **) &colcount, funcname);
	wrapbmp->width = 0;
	wrapbmp->height = 0;
	wrapbmp_line_spacing = -1;
	wrapbmp_gap = -1;
	wrapbmp_rhmax = -1;
	wrapbmp_thmax = -1;
	wrapbmp_hyphen.ch = -1;
	if (use_bgi == 1 && beginning_gap_internal > 0)
		dst_add_gap_src_pixels("wrapbmp_bgi1", masterinfo,
				beginning_gap_internal);
	beginning_gap_internal = -1;
	last_h5050_internal = -1;
	if (use_bgi)
		just_flushed_internal = 1;
}

static void wrapbmp_hyphen_erase(void)

{
	WILLUSBITMAP *bmp, _bmp;
	int bw, bpp, c0, c1, c2, i;

	if (wrapbmp_hyphen.ch < 0)
		return;
#if (WILLUSDEBUGX & 16)
	printf("@hyphen_erase, bmp=%d x %d x %d\n",wrapbmp->width,wrapbmp->height,wrapbmp->bpp);
	printf("    ch=%d, c2=%d, r1=%d, r2=%d\n",wrapbmp_hyphen.ch,wrapbmp_hyphen.c2,wrapbmp_hyphen.r1,wrapbmp_hyphen.r2);
#endif
	bmp = &_bmp;
	bmp_init(bmp);
	bmp->bpp = wrapbmp->bpp;
	if (bmp->bpp == 8)
		for (i = 0; i < 256; i++)
			bmp->red[i] = bmp->blue[i] = bmp->green[i] = i;
	bmp->height = wrapbmp->height;
	if (src_left_to_right) {
		bmp->width = wrapbmp_hyphen.c2 + 1;
		c0 = 0;
		c1 = wrapbmp_hyphen.ch;
		c2 = bmp->width - 1;
	} else {
		bmp->width = wrapbmp->width - wrapbmp_hyphen.c2;
		c0 = wrapbmp_hyphen.c2;
		c1 = 0;
		c2 = wrapbmp_hyphen.ch - wrapbmp_hyphen.c2;
	}
	bmp_alloc(bmp);
	bpp = bmp->bpp == 24 ? 3 : 1;
	bw = bpp * bmp->width;
	for (i = 0; i < bmp->height; i++)
		memcpy(bmp_rowptr_from_top(bmp, i),
				bmp_rowptr_from_top(wrapbmp, i) + bpp * c0, bw);
	bw = (c2 - c1 + 1) * bpp;
	if (bw > 0)
		for (i = wrapbmp_hyphen.r1; i <= wrapbmp_hyphen.r2; i++)
			memset(bmp_rowptr_from_top(bmp, i) + bpp * c1, 255, bw);
#if (WILLUSDEBUGX & 16)
	{
		static int count=1;
		char filename[256];
		sprintf(filename,"be%04d.png",count);
		bmp_write(wrapbmp,filename,stdout,100);
		sprintf(filename,"ae%04d.png",count);
		bmp_write(bmp,filename,stdout,100);
		count++;
	}
#endif
	bmp_copy(wrapbmp, bmp);
	bmp_free(bmp);
}

/*
 ** src is only allocated if dst_color != 0
 */
static void white_margins(WILLUSBITMAP *src, WILLUSBITMAP *srcgrey)

{
	int i, n;
	BMPREGION *region, _region;

	region = &_region;
	region->bmp = srcgrey;
	get_white_margins(region);
	n = region->c1;
	for (i = 0; i < srcgrey->height; i++) {
		unsigned char *p;
		if (dst_color) {
			p = bmp_rowptr_from_top(src, i);
			memset(p, 255, n * 3);
		}
		p = bmp_rowptr_from_top(srcgrey, i);
		memset(p, 255, n);
	}
	n = srcgrey->width - 1 - region->c2;
	for (i = 0; i < srcgrey->height; i++) {
		unsigned char *p;
		if (dst_color) {
			p = bmp_rowptr_from_top(src, i) + 3 * (src->width - n);
			memset(p, 255, n * 3);
		}
		p = bmp_rowptr_from_top(srcgrey, i) + srcgrey->width - n;
		memset(p, 255, n);
	}
	n = region->r1;
	for (i = 0; i < n; i++) {
		unsigned char *p;
		if (dst_color) {
			p = bmp_rowptr_from_top(src, i);
			memset(p, 255, src->width * 3);
		}
		p = bmp_rowptr_from_top(srcgrey, i);
		memset(p, 255, srcgrey->width);
	}
	n = srcgrey->height - 1 - region->r2;
	for (i = srcgrey->height - n; i < srcgrey->height; i++) {
		unsigned char *p;
		if (dst_color) {
			p = bmp_rowptr_from_top(src, i);
			memset(p, 255, src->width * 3);
		}
		p = bmp_rowptr_from_top(srcgrey, i);
		memset(p, 255, srcgrey->width);
	}
}

static void get_white_margins(BMPREGION *region)

{
	int n;
	double defval;

	defval = 0.25;
	if (mar_left < 0.)
		mar_left = defval;
	n = (int) (0.5 + mar_left * src_dpi);
	if (n > region->bmp->width)
		n = region->bmp->width;
	region->c1 = n;
	if (mar_right < 0.)
		mar_right = defval;
	n = (int) (0.5 + mar_right * src_dpi);
	if (n > region->bmp->width)
		n = region->bmp->width;
	region->c2 = region->bmp->width - 1 - n;
	if (mar_top < 0.)
		mar_top = defval;
	n = (int) (0.5 + mar_top * src_dpi);
	if (n > region->bmp->height)
		n = region->bmp->height;
	region->r1 = n;
	if (mar_bot < 0.)
		mar_bot = defval;
	n = (int) (0.5 + mar_bot * src_dpi);
	if (n > region->bmp->height)
		n = region->bmp->height;
	region->r2 = region->bmp->height - 1 - n;
}

/*
 ** bitmap_orientation()
 **
 ** 1.0 means neutral
 **
 ** >> 1.0 means document is likely portrait (no rotation necessary)
 **    (max is 100.)
 **
 ** << 1.0 means document is likely landscape (need to rotate it)
 **    (min is 0.01)
 **
 */
static double bitmap_orientation(WILLUSBITMAP *bmp)

{
	int i, ic, wtcalc;
	double hsum, vsum, rat;

	wtcalc = -1;
	for (vsum = 0., hsum = 0., ic = 0, i = 20; i <= 85; i += 5, ic++) {
		double nv, nh;
		int wth, wtv;

#ifdef DEBUG
		printf("h %d:\n",i);
#endif
		if (ic == 0)
			wth = -1;
		else
			wth = wtcalc;
		wth = -1;
		nh = bmp_inflections_horizontal(bmp, 8, i, &wth);
#ifdef DEBUG
		{
			FILE *f;
			f=fopen("inf.ep","a");
			fprintf(f,"/ag\n");
			fclose(f);
		}
		printf("v %d:\n",i);
#endif
		if (ic == 0)
			wtv = -1;
		else
			wtv = wtcalc;
		wtv = -1;
		nv = bmp_inflections_vertical(bmp, 8, i, &wtv);
		if (ic == 0) {
			if (wtv > wth)
				wtcalc = wtv;
			else
				wtcalc = wth;
			continue;
		}
// exit(10);
		hsum += nh * i * i * i;
		vsum += nv * i * i * i;
	}
	if (vsum == 0. && hsum == 0.)
		rat = 1.0;
	else if (hsum < vsum && hsum / vsum < .01)
		rat = 100.;
	else
		rat = vsum / hsum;
	if (rat < .01)
		rat = .01;
	// printf("    page %2d:  %8.4f\n",pagenum,rat);
	// fprintf(out,"\t%8.4f",vsum/hsum);
	// fprintf(out,"\n");
	return (rat);
}

static double bmp_inflections_vertical(WILLUSBITMAP *srcgrey, int ndivisions,
		int delta, int *wthresh)

{
	int y0, y1, ny, i, nw, nisum, ni, wt, wtmax;
	double *g;
	char *funcname = "bmp_inflections_vertical";

	nw = srcgrey->width / ndivisions;
	y0 = srcgrey->height / 6;
	y1 = srcgrey->height - y0;
	ny = y1 - y0;
	willus_dmem_alloc_warn(21, (void **) &g, ny * sizeof(double), funcname, 10);
	wtmax = -1;
	for (nisum = 0, i = 0; i < 10; i++) {
		int x0, x1, nx, j;

		x0 = (srcgrey->width - nw) * (i + 2) / 13;
		x1 = x0 + nw;
		if (x1 > srcgrey->width)
			x1 = srcgrey->width;
		nx = x1 - x0;
		for (j = y0; j < y1; j++) {
			int k, rsum;
			unsigned char *p;

			p = bmp_rowptr_from_top(srcgrey, j) + x0;
			for (rsum = k = 0; k < nx; k++, p++)
				rsum += p[0];
			g[j - y0] = (double) rsum / nx;
		}
		wt = (*wthresh);
		ni = inflection_count(g, ny, delta, &wt);
		if ((*wthresh) < 0 && ni >= 3 && wt > wtmax)
			wtmax = wt;
		if (ni > nisum)
			nisum = ni;
	}
	willus_dmem_free(21, &g, funcname);
	if ((*wthresh) < 0)
		(*wthresh) = wtmax;
	return (nisum);
}

static double bmp_inflections_horizontal(WILLUSBITMAP *srcgrey, int ndivisions,
		int delta, int *wthresh)

{
	int x0, x1, nx, bw, i, nh, nisum, ni, wt, wtmax;
	double *g;
	char *funcname = "bmp_inflections_vertical";

	nh = srcgrey->height / ndivisions;
	x0 = srcgrey->width / 6;
	x1 = srcgrey->width - x0;
	nx = x1 - x0;
	bw = bmp_bytewidth(srcgrey);
	willus_dmem_alloc_warn(22, (void **) &g, nx * sizeof(double), funcname, 10);
	wtmax = -1;
	for (nisum = 0, i = 0; i < 10; i++) {
		int y0, y1, ny, j;

		y0 = (srcgrey->height - nh) * (i + 2) / 13;
		y1 = y0 + nh;
		if (y1 > srcgrey->height)
			y1 = srcgrey->height;
		ny = y1 - y0;
		for (j = x0; j < x1; j++) {
			int k, rsum;
			unsigned char *p;

			p = bmp_rowptr_from_top(srcgrey, y0) + j;
			for (rsum = k = 0; k < ny; k++, p += bw)
				rsum += p[0];
			g[j - x0] = (double) rsum / ny;
		}
		wt = (*wthresh);
		ni = inflection_count(g, nx, delta, &wt);
		if ((*wthresh) < 0 && ni >= 3 && wt > wtmax)
			wtmax = wt;
		if (ni > nisum)
			nisum = ni;
	}
	willus_dmem_free(22, &g, funcname);
	if ((*wthresh) < 0)
		(*wthresh) = wtmax;
	return (nisum);
}

static int inflection_count(double *x, int n, int delta, int *wthresh)

{
	int i, i0, ni, ww, c, ct, wt, mode;
	double meandi, meandisq, f1, f2, stdev;
	double *xs;
	static int hist[256];
	static char *funcname = "inflection_count";

	/* Find threshold white value that peaks must exceed */
	if ((*wthresh) < 0) {
		for (i = 0; i < 256; i++)
			hist[i] = 0;
		for (i = 0; i < n; i++) {
			i0 = floor(x[i]);
			if (i0 > 255)
				i0 = 255;
			hist[i0]++;
		}
		ct = n * .15;
		for (c = 0, i = 255; i >= 0; i--) {
			c += hist[i];
			if (c > ct)
				break;
		}
		wt = i - 10;
		if (wt < 192)
			wt = 192;
#ifdef DEBUG
		printf("wt=%d\n",wt);
#endif
		(*wthresh) = wt;
	} else
		wt = (*wthresh);
	ww = n / 150;
	if (ww < 1)
		ww = 1;
	willus_dmem_alloc_warn(23, (void **) &xs, sizeof(double) * n, funcname, 10);
	for (i = 0; i < n - ww; i++) {
		int j;
		for (xs[i] = 0., j = 0; j < ww; j++, xs[i] += x[i + j])
			;
		xs[i] /= ww;
	}
	meandi = meandisq = 0.;
	if (xs[0] <= wt - delta)
		mode = 1;
	else if (xs[0] >= wt)
		mode = -1;
	else
		mode = 0;
	for (i0 = 0, ni = 0, i = 1; i < n - ww; i++) {
		if (mode == 1 && xs[i] >= wt) {
			if (i0 > 0) {
				meandi += i - i0;
				meandisq += (i - i0) * (i - i0);
				ni++;
			}
			i0 = i;
			mode = -1;
			continue;
		}
		if (xs[i] <= wt - delta)
			mode = 1;
	}
	stdev = 1.0; /* Avoid compiler warning */
	if (ni > 0) {
		meandi /= ni;
		meandisq /= ni;
		stdev = sqrt(fabs(meandi * meandi - meandisq));
	}
	f1 = meandi / n;
	if (f1 > .15)
		f1 = .15;
	if (ni > 2) {
		if (stdev / meandi < .05)
			f2 = 20.;
		else
			f2 = meandi / stdev;
	} else
		f2 = 1.;
#ifdef DEBUG
	printf("    ni=%3d, f1=%8.4f, f2=%8.4f, f1*f2*ni=%8.4f\n",ni,f1,f2,f1*f2*ni);
	{
		static int count=0;
		FILE *f;
		int i;
		f=fopen("inf.ep",count==0?"w":"a");
		count++;
		fprintf(f,"/sa l \"%d\" 1\n",ni);
		for (i=0;i<n-ww;i++)
		fprintf(f,"%g\n",xs[i]);
		fprintf(f,"//nc\n");
		fclose(f);
	}
#endif /* DEBUG */
	willus_dmem_free(23, &xs, funcname);
	return (f1 * f2 * ni);
}

static void pdfboxes_init(PDFBOXES *boxes)

{
	boxes->n = boxes->na = 0;
	boxes->box = NULL;
}

static void pdfboxes_free(PDFBOXES *boxes)

{
	static char *funcname = "pdfboxes_free";
	willus_dmem_free(24, (double **) &boxes->box, funcname);
}

#ifdef COMMENT
static void pdfboxes_add_box(PDFBOXES *boxes,PDFBOX *box)

{
	static char *funcname="pdfboxes_add_box";

	if (boxes->n>=boxes->na)
	{
		int newsize;

		newsize = boxes->na < 1024 ? 2048 : boxes->na*2;
		/* Just calls willus_mem_alloc if oldsize==0 */
		willus_mem_realloc_robust_warn((void **)&boxes->box,newsize*sizeof(PDFBOX),
				boxes->na*sizeof(PDFBOX),funcname,10);
		boxes->na=newsize;
	}
	boxes->box[boxes->n++]=(*box);
}

static void pdfboxes_delete(PDFBOXES *boxes,int n)

{
	if (n>0 && n<boxes->n)
	{
		int i;
		for (i=0;i<boxes->n-n;i++)
		boxes->box[i]=boxes->box[i+n];
	}
	boxes->n -= n;
	if (boxes->n < 0)
	boxes->n = 0;
}
#endif

/*
 ** Track gaps between words so that we can tell when one is out of family.
 ** lcheight = height of a lowercase letter.
 */
static void word_gaps_add(BREAKINFO *breakinfo, int lcheight,
		double *median_gap)

{
	static int nn = 0;
	static double gap[1024];
	static char *funcname = "word_gaps_add";

	if (breakinfo != NULL && breakinfo->n > 1) {
		int i;

		for (i = 0; i < breakinfo->n - 1; i++) {
			double g;
			g = (double) breakinfo->textrow[i].gap / lcheight;
			if (g >= word_spacing) {
				gap[nn & 0x3ff] = g;
				nn++;
			}
		}
	}
	if (median_gap != NULL) {
		if (nn > 0) {
			int n;
			static double *gap_sorted;

			n = (nn > 1024) ? 1024 : nn;
			willus_dmem_alloc_warn(28, (void **) &gap_sorted,
					sizeof(double) * n, funcname, 10);
			memcpy(gap_sorted, gap, n * sizeof(double));
			sortd(gap_sorted, n);
			(*median_gap) = gap_sorted[n / 2];
			willus_dmem_free(28, &gap_sorted, funcname);
		} else
			(*median_gap) = 0.7;
	}
}

/*
 ** bmp must be grayscale! (cbmp = color, can be null)
 */
static void bmp_detect_vertical_lines(WILLUSBITMAP *bmp, WILLUSBITMAP *cbmp,
		double dpi, double minwidth_in, double maxwidth_in, double minheight_in,
		double anglemax_deg, int white_thresh)

{
	int tc, iangle, irow, icol;
	int rowstep, na, angle_sign, ccthresh;
	int pixmin, halfwidth, bytewidth;
	int bs1, nrsteps, dp;
	double anglestep;
	WILLUSBITMAP *tmp, _tmp;
	unsigned char *p0;

	if (debug)
		printf("At bmp_detect_vertical_lines...\n");
	if (!bmp_is_grayscale(bmp)) {
		printf(
				"Internal error.  bmp_detect_vertical_lines passed a non-grayscale bitmap.\n");
		exit(10);
	}
	tmp = &_tmp;
	bmp_init(tmp);
	bmp_copy(tmp, bmp);
	dp = bmp_rowptr_from_top(tmp, 0) - bmp_rowptr_from_top(bmp, 0);
	bytewidth = bmp_bytewidth(bmp);
	pixmin = (int) (minwidth_in * dpi + .5);
	if (pixmin < 1)
		pixmin = 1;
	halfwidth = pixmin / 4;
	if (halfwidth < 1)
		halfwidth = 1;
	anglestep = atan2((double) halfwidth / dpi, minheight_in);
	na = (int) ((anglemax_deg * PI / 180.) / anglestep + .5);
	if (na < 1)
		na = 1;
	rowstep = (int) (dpi / 40. + .5);
	if (rowstep < 2)
		rowstep = 2;
	nrsteps = bmp->height / rowstep;
	bs1 = bytewidth * rowstep;
	ccthresh = (int) (minheight_in * dpi / rowstep + .5);
	if (ccthresh < 2)
		ccthresh = 2;
	if (debug && verbose)
		printf(
				"    na = %d, rowstep = %d, ccthresh = %d, white_thresh = %d, nrsteps=%d\n",
				na, rowstep, ccthresh, white_thresh, nrsteps);
	/*
	 bmp_write(bmp,"out.png",stdout,97);
	 wfile_written_info("out.png",stdout);
	 */
	p0 = bmp_rowptr_from_top(bmp, 0);
	for (tc = 0; tc < 100; tc++) {
		int ccmax, ic0max, ir0max;
		double tanthmax;

		ccmax = -1;
		ic0max = ir0max = 0;
		tanthmax = 0.;
		for (iangle = 0; iangle <= na; iangle++) {
			for (angle_sign = 1; angle_sign >= -1; angle_sign -= 2) {
				double th, tanth, tanthx;
				int ic1, ic2;

				if (iangle == 0 && angle_sign == -1)
					continue;
				th = (PI / 180.) * iangle * angle_sign * fabs(anglemax_deg)
						/ na;
				tanth = tan(th);
				tanthx = tanth * rowstep;
				if (angle_sign == 1) {
					ic1 = -(int) (bmp->height * tanth + 1.);
					ic2 = bmp->width - 1;
				} else {
					ic1 = (int) (-bmp->height * tanth + 1.);
					ic2 = bmp->width - 1 + (int) (-bmp->height * tanth + 1.);
				}
// printf("iangle=%2d, angle_sign=%2d, ic1=%4d, ic2=%4d\n",iangle,angle_sign,ic1,ic2);
				for (icol = ic1; icol <= ic2; icol++) {
					unsigned char *p;
					int cc, ic0, ir0;
					p = p0;
					if (icol < 0 || icol > bmp->width - 1)
						for (irow = 0; irow < nrsteps; irow++, p += bs1) {
							int ic;
							ic = icol + irow * tanthx;
							if (ic >= 0 && ic < bmp->width)
								break;
						}
					else
						irow = 0;
					for (ir0 = ic0 = cc = 0; irow < nrsteps; irow++, p += bs1) {
						int ic;
						ic = icol + irow * tanthx;
						if (ic < 0 || ic >= bmp->width)
							break;
						if ((p[ic] < white_thresh
								|| p[ic + bytewidth] < white_thresh)
								&& (p[ic + dp] < white_thresh
										|| p[ic + bytewidth + dp] < white_thresh)) {
							if (cc == 0) {
								ic0 = ic;
								ir0 = irow * rowstep;
							}
							cc++;
							if (cc > ccmax) {
								ccmax = cc;
								tanthmax = tanth;
								ic0max = ic0;
								ir0max = ir0;
							}
						} else
							cc = 0;
					}
				}
			}
		}
		if (ccmax < ccthresh)
			break;
		if (debug)
			printf(
					"    Vert line detected:  ccmax=%d (pix=%d), tanthmax=%g, ic0max=%d, ir0max=%d\n",
					ccmax, ccmax * rowstep, tanthmax, ic0max, ir0max);
		if (!vert_line_erase(bmp, cbmp, tmp, ir0max, ic0max, tanthmax,
				minheight_in, minwidth_in, maxwidth_in, white_thresh))
			break;
	}
	/*
	 bmp_write(tmp,"outt.png",stdout,95);
	 wfile_written_info("outt.png",stdout);
	 bmp_write(bmp,"out2.png",stdout,95);
	 wfile_written_info("out2.png",stdout);
	 exit(10);
	 */
}

/*
 ** Calculate max vert line length.  Line is terminated by nw consecutive white pixels
 ** on either side.
 */
static int vert_line_erase(WILLUSBITMAP *bmp, WILLUSBITMAP *cbmp,
		WILLUSBITMAP *tmp, int row0, int col0, double tanth,
		double minheight_in, double minwidth_in, double maxwidth_in,
		int white_thresh)

{
	int lw, cc, maxdev, nw, dir, i, n;
	int *c1, *c2, *w;
	static char *funcname = "vert_line_erase";

	willus_dmem_alloc_warn(26, (void **) &c1, sizeof(int) * 3 * bmp->height,
			funcname, 10);
	c2 = &c1[bmp->height];
	w = &c2[bmp->height];
	/*
	 maxdev = (int)((double)bmp->height / minheight_in +.5);
	 if (maxdev < 3)
	 maxdev=3;
	 */
	nw = (int) ((double) src_dpi / 100. + .5);
	if (nw < 2)
		nw = 2;
	maxdev = nw;
	for (i = 0; i < bmp->height; i++)
		c1[i] = c2[i] = -1;
	n = 0;
	for (dir = -1; dir <= 1; dir += 2) {
		int del, brc;

		brc = 0;
		for (del = (dir == -1) ? 0 : 1; 1; del++) {
			int r, c;
			unsigned char *p;

			r = row0 + dir * del;
			if (r < 0 || r > bmp->height - 1)
				break;
			c = col0 + (r - row0) * tanth;
			if (c < 0 || c > bmp->width - 1)
				break;
			p = bmp_rowptr_from_top(bmp, r);
			for (i = c; i <= c + maxdev && i < bmp->width; i++)
				if (p[i] < white_thresh)
					break;
			if (i > c + maxdev || i >= bmp->width) {
				for (i = c - 1; i >= c - maxdev && i >= 0; i--)
					if (p[i] < white_thresh)
						break;
				if (i < c - maxdev || i < 0) {
					brc++;
					if (brc >= nw)
						break;
					continue;
				}
			}
			brc = 0;
			for (c = i, cc = 0; i < bmp->width; i++)
				if (p[i] < white_thresh)
					cc = 0;
				else {
					cc++;
					if (cc >= nw)
						break;
				}
			c2[r] = i - cc;
			if (c2[r] > bmp->width - 1)
				c2[r] = bmp->width - 1;
			for (cc = 0, i = c; i >= 0; i--)
				if (p[i] < white_thresh)
					cc = 0;
				else {
					cc++;
					if (cc >= nw)
						break;
				}
			c1[r] = i + cc;
			if (c1[r] < 0)
				c1[r] = 0;
			w[n++] = c2[r] - c1[r] + 1;
			c1[r] -= cc;
			if (c1[r] < 0)
				c1[r] = 0;
			c2[r] += cc;
			if (c2[r] > bmp->width - 1)
				c2[r] = bmp->width - 1;
		}
	}
	if (n > 1)
		sorti(w, n);
	if (n < 10 || n < minheight_in * src_dpi || w[n / 4] < minwidth_in * src_dpi
			|| w[3 * n / 4] > maxwidth_in * src_dpi
			|| (erase_vertical_lines == 1 && w[n - 1] > maxwidth_in * src_dpi)) {
		/* Erase area in temp bitmap */
		for (i = 0; i < bmp->height; i++) {
			unsigned char *p;
			int cmax;

			if (c1[i] < 0 || c2[i] < 0)
				continue;
			cmax = (c2[i] - c1[i]) + 1;
			p = bmp_rowptr_from_top(tmp, i) + c1[i];
			for (; cmax > 0; cmax--, p++)
				(*p) = 255;
		}
	} else {
		/* Erase line width in source bitmap */
		lw = w[3 * n / 4] + nw * 2;
		if (lw > maxwidth_in * src_dpi / 2)
			lw = maxwidth_in * src_dpi / 2;
		for (i = 0; i < bmp->height; i++) {
			unsigned char *p;
			int c0, cmin, cmax, count, white;

			if (c1[i] < 0 || c2[i] < 0)
				continue;
			c0 = col0 + (i - row0) * tanth;
			cmin = c0 - lw - 1;
			if (cmin < c1[i])
				cmin = c1[i];
			cmax = c0 + lw + 1;
			if (cmax > c2[i])
				cmax = c2[i];
			p = bmp_rowptr_from_top(bmp, i);
			c0 = (p[cmin] > p[cmax]) ? cmin : cmax;
			white = p[c0];
			if (white <= white_thresh)
				white = white_thresh + 1;
			if (white > 255)
				white = 255;
			count = (cmax - cmin) + 1;
			p = &p[cmin];
			for (; count > 0; count--, p++)
				(*p) = white;
			if (cbmp != NULL) {
				unsigned char *p0;
				p = bmp_rowptr_from_top(cbmp, i);
				p0 = p + c0 * 3;
				p = p + cmin * 3;
				count = (cmax - cmin) + 1;
				for (; count > 0; count--, p += 3) {
					p[0] = p0[0];
					p[1] = p0[1];
					p[2] = p0[2];
				}
			}
		}
	}
	willus_dmem_free(26, (double **) &c1, funcname);
	return (1);
}

/*
 ** mem_index... controls which memory allocactions get a protective margin
 ** around them.
 */
static int mem_index_min = 999;
static int mem_index_max = 999;
static void willus_dmem_alloc_warn(int index, void **ptr, int size,
		char *funcname, int exitcode)

{
	if (index >= mem_index_min && index <= mem_index_max) {
		char *ptr1;
		void *x;
		willus_mem_alloc_warn((void **) &ptr1, size + 2048, funcname, exitcode);
		ptr1 += 1024;
		x = (void *) ptr1;
		(*ptr) = x;
	} else
		willus_mem_alloc_warn(ptr, size, funcname, exitcode);
}

static void willus_dmem_free(int index, double **ptr, char *funcname)

{
	if ((*ptr) == NULL)
		return;
	if (index >= mem_index_min && index <= mem_index_max) {
		double *x;
		char *ptr1;
		x = (*ptr);
		ptr1 = (char *) x;
		ptr1 -= 1024;
		x = (double *) ptr1;
		willus_mem_free(&x, funcname);
		(*ptr) = NULL;
	} else
		willus_mem_free(ptr, funcname);
}

/* mem.c */
/*
** The reason I don't simply use malloc is because I want to allocate
** memory using type long instead of type size_t.  On some compilers,
** like gcc, these are the same, so it doesn't matter.  On other
** compilers, like Turbo C, these are different.
**
*/
static int willus_mem_alloc(double **ptr,long size,char *name)

    {
#if (defined(WIN32) && !defined(__DMC__))
    unsigned long memsize;
    memsize = (unsigned long)size;
#ifdef USEGLOBAL
    (*ptr) = (memsize==size) ? (double *)GlobalAlloc(GPTR,memsize) : NULL;
#else
    (*ptr) = (memsize==size) ? (double *)CoTaskMemAlloc(memsize) : NULL;
#endif
#else
    size_t  memsize;
    memsize=(size_t)size;
    (*ptr) =  (memsize==size) ? (double *)malloc(memsize) : NULL;
#endif
/*
{
f=fopen("mem.dat","a");
fprintf(f,"willus_mem_alloc(%d,%s)\n",size,name);
fclose(f);
}
*/
    return((*ptr)!=NULL);
    }

/*
** Prints an integer to 's' with commas separating every three digits.
** E.g. 45,399,350
** Correctly handles negative values.
*/
static void comma_print(char *s,long size)

    {
    int  i,m,neg;
    char tbuf[80];

    if (!size)
        {
        s[0]='0';
        s[1]='\0';
        return;
        }
    s[0]='\0';
    neg=0;
    if (size<0)
        {
        size=-size;
        neg=1;
        }
    for (i=0,m=size%1000;size;i++,size=(size-m)/1000,m=size%1000)
        {
        sprintf(tbuf,m==size ? "%d%s":"%03d%s",m,i>0 ? "," : "");
        strcat(tbuf,s);
        strcpy(s,tbuf);
        }
    if (neg)
        {
        strcpy(tbuf,"-");
        strcat(tbuf,s);
        strcpy(s,tbuf);
        }
    }


static void mem_warn(char *name,int size,int exitcode)

    {
    static char buf[128];

    aprintf("\n" ANSI_RED "\aCannot allocate enough memory for "
            "function %s." ANSI_NORMAL "\n",name);
    comma_print(buf,size);
    aprintf("    " ANSI_RED "(Needed %s bytes.)" ANSI_NORMAL "\n\n",buf);
    if (exitcode!=0)
        {
        aprintf("    " ANSI_RED "Program terminated." ANSI_NORMAL "\n\n");
        exit(exitcode);
        }
    }

static int willus_mem_alloc_warn(void **ptr, int size, char *name, int exitcode)

{
	int status;

	status = willus_mem_alloc((double **) ptr, (long) size, name);
	if (!status)
		mem_warn(name, size, exitcode);
	return (status);
}

static void willus_mem_free(double **ptr, char *name)

{
	if ((*ptr) != NULL) {
#if (defined(WIN32) && !defined(__DMC__))
#ifdef USEGLOBAL
		GlobalFree((void *)(*ptr));
#else
		CoTaskMemFree((void *)(*ptr));
#endif
#else
		free((void *) (*ptr));
#endif
		(*ptr) = NULL;
	}
}

static int willus_mem_realloc_robust(double **ptr,long newsize,long oldsize,char *name)

    {
#if (defined(WIN32) && !defined(__DMC__))
    unsigned long memsize;
    void *newptr;
#else
    size_t  memsize;
    void *newptr;
#endif

#if (defined(WIN32) && !defined(__DMC__))
    memsize=(unsigned long)newsize;
#else
    memsize=(size_t)newsize;
#endif
    if (memsize!=newsize)
        return(0);
    if ((*ptr)==NULL || oldsize<=0)
        return(willus_mem_alloc(ptr,newsize,name));
#if (defined(WIN32) && !defined(__DMC__))
#ifdef USEGLOBAL
    newptr = (void *)GlobalReAlloc((void *)(*ptr),memsize,GMEM_MOVEABLE);
#else
    newptr = (void *)CoTaskMemRealloc((void *)(*ptr),memsize);
#endif
#else
    newptr = realloc((void *)(*ptr),memsize);
#endif
    if (newptr==NULL && willus_mem_alloc((double **)&newptr,newsize,name))
        {
        memcpy(newptr,(*ptr),oldsize);
        willus_mem_free(ptr,name);
        }
    if (newptr==NULL)
        return(0);

    (*ptr) = newptr;
    return(1);
    }


static int willus_mem_realloc_robust_warn(void **ptr,int newsize,int oldsize,char *name,
                                int exitcode)

    {
    int status;

    status = willus_mem_realloc_robust((double **)ptr,newsize,oldsize,name);
    if (!status)
        mem_warn(name,newsize,exitcode);
    return(status);
    }

/* math.c */
static void sortd(double *x, int n)

{
	int top, n1;
	double x0;

	if (n < 2)
		return;
	top = n / 2;
	n1 = n - 1;
	while (1) {
		if (top > 0) {
			top--;
			x0 = x[top];
		} else {
			x0 = x[n1];
			x[n1] = x[0];
			n1--;
			if (!n1) {
				x[0] = x0;
				return;
			}
		}
		{
			int parent, child;

			parent = top;
			child = top * 2 + 1;
			while (child <= n1) {
				if (child < n1 && x[child] < x[child + 1])
					child++;
				if (x0 < x[child]) {
					x[parent] = x[child];
					parent = child;
					child += (parent + 1);
				} else
					break;
			}
			x[parent] = x0;
		}
	}
}

static void sorti(int *x, int n)

{
	int top, n1;
	int x0;

	if (n < 2)
		return;
	top = n / 2;
	n1 = n - 1;
	while (1) {
		if (top > 0) {
			top--;
			x0 = x[top];
		} else {
			x0 = x[n1];
			x[n1] = x[0];
			n1--;
			if (!n1) {
				x[0] = x0;
				return;
			}
		}
		{
			int parent, child;

			parent = top;
			child = top * 2 + 1;
			while (child <= n1) {
				if (child < n1 && x[child] < x[child + 1])
					child++;
				if (x0 < x[child]) {
					x[parent] = x[child];
					parent = child;
					child += (parent + 1);
				} else
					break;
			}
			x[parent] = x0;
		}
	}
}

/* bmp.c */
/*
 ** Should call bmp_set_type() right after this to set the bitmap type.
 */

#define RGBSET24(bmp,ptr,r,g,b) \
    if (bmp->type==WILLUSBITMAP_TYPE_NATIVE) \
        { \
        ptr[0]=r; \
        ptr[1]=g; \
        ptr[2]=b; \
        } \
    else \
        { \
        ptr[2]=r; \
        ptr[1]=g; \
        ptr[0]=b; \
        }

#define RGBGET(bmp,ptr,r,g,b) \
    if (bmp->bpp==8) \
        { \
        r=bmp->red[ptr[0]]; \
        g=bmp->green[ptr[0]]; \
        b=bmp->blue[ptr[0]]; \
        } \
    else if (bmp->type==WILLUSBITMAP_TYPE_NATIVE) \
        { \
        r=ptr[0]; \
        g=ptr[1]; \
        b=ptr[2]; \
        } \
    else \
        { \
        r=ptr[2]; \
        g=ptr[1]; \
        b=ptr[0]; \
        }

#define RGBGETINCPTR(bmp,ptr,r,g,b) \
    if (bmp->bpp==8) \
        { \
        r=bmp->red[ptr[0]]; \
        g=bmp->green[ptr[0]]; \
        b=bmp->blue[ptr[0]]; \
        ptr++; \
        } \
    else if (bmp->type==WILLUSBITMAP_TYPE_NATIVE) \
        { \
        r=ptr[0]; \
        g=ptr[1]; \
        b=ptr[2]; \
        ptr+=3; \
        } \
    else \
        { \
        r=ptr[2]; \
        g=ptr[1]; \
        b=ptr[0]; \
        ptr+=3; \
        }

static void bmp_init(WILLUSBITMAP *bmap)

{
	bmap->data = NULL;
	bmap->size_allocated = 0;
	bmap->type = WILLUSBITMAP_TYPE_NATIVE;
}

static int bmp_bytewidth_win32(WILLUSBITMAP *bmp)

    {
    return(((bmp->bpp==24 ? bmp->width*3 : bmp->width)+3)&(~0x3));
    }

/*
 ** The width, height, and bpp parameters of the WILLUSBITMAP structure
 ** should be set before calling this function.
 */
static int bmp_alloc(WILLUSBITMAP *bmap)

{
	int size;
	static char *funcname = "bmp_alloc";

	if (bmap->bpp != 8 && bmap->bpp != 24) {
		printf("Internal error:  call to bmp_alloc has bpp!=8 and bpp!=24!\n");
		exit(10);
	}
	/* Choose the max size even if not WIN32 to avoid memory faults */
	/* and to allow the possibility of changing the "type" of the   */
	/* bitmap without reallocating memory.                          */
	size = bmp_bytewidth_win32(bmap) * bmap->height;
	if (bmap->data != NULL && bmap->size_allocated >= size)
		return (1);
	if (bmap->data != NULL)
		willus_mem_realloc_robust_warn((void **) &bmap->data, size,
				bmap->size_allocated, funcname, 10);
	else
		willus_mem_alloc_warn((void **) &bmap->data, size, funcname, 10);
	bmap->size_allocated = size;
	return (1);
}

static void bmp_free(WILLUSBITMAP *bmap)

    {
    if (bmap->data!=NULL)
        {
        willus_mem_free((double **)&bmap->data,"bmp_free");
        bmap->data=NULL;
        bmap->size_allocated=0;
        }
    }

/*
** If 8-bit, the bitmap is filled with <r>.
** If 24-bit, it gets <r>, <g>, <b> values.
*/
static void bmp_fill(WILLUSBITMAP *bmp,int r,int g,int b)

    {
    int     y,n;

    if (bmp->bpp==8 || (r==g && r==b))
        {
        memset(bmp->data,r,bmp->size_allocated);
        return;
        }
    if (bmp->type==WILLUSBITMAP_TYPE_WIN32 && bmp->bpp==24)
        {
        y=r;
        r=b;
        b=y;
        }
    for (y=bmp->height-1;y>=0;y--)
        {
        unsigned char *p;

        p=bmp_rowptr_from_top(bmp,y);
        for (n=bmp->width-1;n>=0;n--)
            {
            (*p)=r;
            p++;
            (*p)=g;
            p++;
            (*p)=b;
            p++;
            }
        }
    }


static int bmp_copy(WILLUSBITMAP *dest, WILLUSBITMAP *src)

{
	dest->width = src->width;
	dest->height = src->height;
	dest->bpp = src->bpp;
	dest->type = src->type;
	if (!bmp_alloc(dest))
		return (0);
	memcpy(dest->data, src->data, src->height * bmp_bytewidth(src));
	memcpy(dest->red, src->red, sizeof(int) * 256);
	memcpy(dest->green, src->green, sizeof(int) * 256);
	memcpy(dest->blue, src->blue, sizeof(int) * 256);
	return (1);
}

static int bmp_bytewidth(WILLUSBITMAP *bmp) {
	return (bmp->bpp == 24 ? bmp->width * 3 : bmp->width);
}

/*
 ** row==0             ==> top row of bitmap
 ** row==bmp->height-1 ==> bottom row of bitmap
 ** (regardless of bitmap type)
 */
static unsigned char *bmp_rowptr_from_top(WILLUSBITMAP *bmp, int row)

{
	if (bmp->type == WILLUSBITMAP_TYPE_WIN32)
		return (&bmp->data[bmp_bytewidth(bmp) * (bmp->height - 1 - row)]);
	else
		return (&bmp->data[bmp_bytewidth(bmp) * row]);
}

/*
 ** Allocate more bitmap rows.
 ** ratio typically something like 1.5 or 2.0
 */
static void bmp_more_rows(WILLUSBITMAP *bmp, double ratio, int pixval)

{
	int new_height, new_bytes, bw;
	static char *funcname = "bmp_more_rows";

	new_height = (int) (bmp->height * ratio + .5);
	if (new_height <= bmp->height)
		return;
	bw = bmp_bytewidth(bmp);
	new_bytes = bw * new_height;
	if (new_bytes > bmp->size_allocated) {
		willus_mem_realloc_robust_warn((void **) &bmp->data, new_bytes,
				bmp->size_allocated, funcname, 10);
		bmp->size_allocated = new_bytes;
	}
	/* Fill in */
	memset(bmp_rowptr_from_top(bmp, bmp->height), pixval,
			(new_height - bmp->height) * bw);
	bmp->height = new_height;
}

static double resample_single(double *y,double x1,double x2)

    {
    int i,i1,i2;
    double dx,dx1,dx2,sum;

    i1=floor(x1);
    i2=floor(x2);
    if (i1==i2)
        return(y[i1]);
    dx=x2-x1;
    if (dx>1.)
        dx=1.;
    dx1= 1.-(x1-i1);
    dx2= x2-i2;
    sum=0.;
    if (dx1 > 1e-8*dx)
        sum += dx1*y[i1];
    if (dx2 > 1e-8*dx)
        sum += dx2*y[i2];
    for (i=i1+1;i<=i2-1;sum+=y[i],i++);
    return(sum/(x2-x1));
    }

/*
** Resample src[] into dst[].
** Examples:  resample_1d(dst,src,0.,5.,5) would simply copy the
**            first five elements of src[] to dst[].
**
**            resample_1d(dst,src,0.,5.,10) would work as follows:
**                dst[0] and dst[1] would get src[0].
**                dst[2] and dst[3] would get src[1].
**                and so on.
**
*/
static void resample_1d(double *dst,double *src,double x1,double x2,
                        int n)

    {
    int i;
    double new,last;

    last=x1;
    for (i=0;i<n;i++)
        {
        new=x1+(x2-x1)*(i+1)/n;
        dst[i] = resample_single(src,last,new);
        last=new;
        }
    }

static void bmp_resample_1(double *tempbmp,WILLUSBITMAP *src,double x1,double y1,
                           double x2,double y2,int newwidth,int newheight,
                           double *temprow,int color)

    {
    int row,col,x0,dx,y0,dy;

    x0=floor(x1);
    dx=ceil(x2)-x0;
    x1-=x0;
    x2-=x0;
    y0=floor(y1);
    dy=ceil(y2)-y0;
    y1-=y0;
    y2-=y0;
    if (src->type==WILLUSBITMAP_TYPE_WIN32 && color>=0)
        color=2-color;
    for (row=0;row<dy;row++)
        {
        unsigned char *p;
        p=bmp_rowptr_from_top(src,row+y0);
        if (src->bpp==8)
            {
            switch (color)
                {
                case -1:
                    for (col=0,p+=x0;col<dx;col++,p++)
                        temprow[col]=p[0];
                    break;
                case 0:
                    for (col=0,p+=x0;col<dx;col++,p++)
                        temprow[col]=src->red[p[0]];
                    break;
                case 1:
                    for (col=0,p+=x0;col<dx;col++,p++)
                        temprow[col]=src->green[p[0]];
                    break;
                case 2:
                    for (col=0,p+=x0;col<dx;col++,p++)
                        temprow[col]=src->blue[p[0]];
                    break;
                }
            }
        else
            {
            p+=color;
            for (col=0,p+=3*x0;col<dx;temprow[col]=p[0],col++,p+=3);
            }
        resample_1d(&tempbmp[row*newwidth],temprow,x1,x2,newwidth);
        }
    for (col=0;col<newwidth;col++)
        {
        double *p,*s;
        p=&tempbmp[col];
        s=&temprow[dy];
        for (row=0;row<dy;row++,p+=newwidth)
            temprow[row]=p[0];
        resample_1d(s,temprow,y1,y2,newheight);
        p=&tempbmp[col];
        for (row=0;row<newheight;row++,p+=newwidth,s++)
            p[0]=s[0];
        }
    }

/*
 ** Resample (re-size) bitmap.  The pixel positions left to right go from
 ** 0.0 to src->width (x-coord), and top to bottom go from
 ** 0.0 to src->height (y-coord).
 ** The cropped rectangle (x1,y1) to (x2,y2) is placed into
 ** the destination bitmap, which need not be allocated yet.
 **
 ** The destination bitmap will be 8-bit grayscale if the source bitmap
 ** passes the bmp_is_grayscale() function.  Otherwise it will be 24-bit.
 **
 ** Returns 0 for okay.
 **         -1 for not enough memory.
 **         -2 for bad cropping area or destination bitmap size
 */
static int bmp_resample(WILLUSBITMAP *dest, WILLUSBITMAP *src, double x1,
		double y1, double x2, double y2, int newwidth, int newheight)

{
	int gray, maxlen, colorplanes;
	double t;
	double *tempbmp;
	double *temprow;
	int color, hmax, row, col, dy;
	static char *funcname = "bmp_resample";

	/* Clip and sort x1,y1 and x2,y2 */
	if (x1 > src->width)
		x1 = src->width;
	else if (x1 < 0.)
		x1 = 0.;
	if (x2 > src->width)
		x2 = src->width;
	else if (x2 < 0.)
		x2 = 0.;
	if (y1 > src->height)
		y1 = src->height;
	else if (y1 < 0.)
		y1 = 0.;
	if (y2 > src->height)
		y2 = src->height;
	else if (y2 < 0.)
		y2 = 0.;
	if (x2 < x1) {
		t = x2;
		x2 = x1;
		x1 = t;
	}
	if (y2 < y1) {
		t = y2;
		y2 = y1;
		y1 = t;
	}
	dy = y2 - y1;
	dy += 2;
	if (x2 - x1 == 0. || y2 - y1 == 0.)
		return (-2);

	/* Allocate temp storage */
	maxlen = x2 - x1 > dy + newheight ? (int) (x2 - x1) : dy + newheight;
	maxlen += 16;
	hmax = newheight > dy ? newheight : dy;
	if (!willus_mem_alloc(&temprow, maxlen * sizeof(double), funcname))
		return (-1);
	if (!willus_mem_alloc(&tempbmp, hmax * newwidth * sizeof(double),
			funcname)) {
		willus_mem_free(&temprow, funcname);
		return (-1);
	}
	if ((gray = bmp_is_grayscale(src)) != 0) {
		int i;
		dest->bpp = 8;
		for (i = 0; i < 256; i++)
			dest->red[i] = dest->blue[i] = dest->green[i] = i;
	} else
		dest->bpp = 24;
	dest->width = newwidth;
	dest->height = newheight;
	dest->type = WILLUSBITMAP_TYPE_NATIVE;
	if (!bmp_alloc(dest)) {
		willus_mem_free(&tempbmp, funcname);
		willus_mem_free(&temprow, funcname);
		return (-1);
	}
	colorplanes = gray ? 1 : 3;
	for (color = 0; color < colorplanes; color++) {
		bmp_resample_1(tempbmp, src, x1, y1, x2, y2, newwidth, newheight,
				temprow, gray ? -1 : color);
		for (row = 0; row < newheight; row++) {
			unsigned char *p;
			double *s;
			p = bmp_rowptr_from_top(dest, row) + color;
			s = &tempbmp[row * newwidth];
			if (colorplanes == 1)
				for (col = 0; col < newwidth;
						p[0] = (int) (s[0] + .5), col++, s++, p++)
					;
			else
				for (col = 0; col < newwidth;
						p[0] = (int) (s[0] + .5), col++, s++, p += colorplanes)
					;
		}
	}
	willus_mem_free(&tempbmp, funcname);
	willus_mem_free(&temprow, funcname);
	return (0);
}

static int bmp8_greylevel_convert(int r,int g,int b)

    {
    return((int)((r*0.3+g*0.59+b*0.11)*1.002));
    }

/*
** One of dest or src can be NULL, which is the
** same as setting them equal to each other, but
** in this case, the bitmap must be 24-bit!
*/
static int bmp_is_grayscale(WILLUSBITMAP *bmp)

    {
    int i;
    if (bmp->bpp!=8)
        return(0);
    for (i=0;i<256;i++)
        if (bmp->red[i]!=i || bmp->green[i]!=i || bmp->blue[i]!=i)
            return(0);
    return(1);
    }

static void bmp_color_xform8(WILLUSBITMAP *dest,WILLUSBITMAP *src,unsigned char *newval)

    {
    int i,ir;

    if (src==NULL)
        src=dest;
    if (dest==NULL)
        dest=src;
    if (dest!=src)
        {
        dest->width = src->width;
        dest->height = src->height;
        dest->bpp = 8;
        for (i=0;i<256;i++)
            dest->red[i]=dest->green[i]=dest->blue[i]=i;
        bmp_alloc(dest);
        }
    for (ir=0;ir<src->height;ir++)
        {
        unsigned char *sp,*dp;
        sp=bmp_rowptr_from_top(src,ir);
        dp=bmp_rowptr_from_top(dest,ir);
        for (i=0;i<src->width;i++)
            dp[i]=newval[sp[i]];
        }
    }

/*
** One of dest or src can be NULL, which is the
** same as setting them equal to each other, but
** in this case, the bitmap must be 24-bit!
*/
static void bmp_color_xform(WILLUSBITMAP *dest,WILLUSBITMAP *src,unsigned char *newval)

    {
    int ir,ic;

    if (src==NULL)
        src=dest;
    if (dest==NULL)
        dest=src;
    if (bmp_is_grayscale(src))
        {
        bmp_color_xform8(dest,src,newval);
        return;
        }
    if (dest!=src)
        {
        dest->width = src->width;
        dest->height = src->height;
        dest->bpp = 24;
        bmp_alloc(dest);
        }
    for (ir=0;ir<src->height;ir++)
        {
        unsigned char *sp,*dp;
        sp=bmp_rowptr_from_top(src,ir);
        dp=bmp_rowptr_from_top(dest,ir);
        for (ic=0;ic<src->width;ic++,dp+=3)
            {
            int r,g,b;

            RGBGETINCPTR(src,sp,r,g,b);
            r=newval[r];
            g=newval[g];
            b=newval[b];
            RGBSET24(dest,dp,r,g,b);
            }
        }
    }

/*
** One of dest or src can be NULL, which is the
** same as setting them equal to each other, but
** in this case, the bitmap must be 24-bit!
** Note: contrast > 1 will increase the contrast.
**       contrast < 1 will decrease the contrast.
**       contrast of 0 will make all pixels the same value.
**       contrast of 1 will not change the image.
*/
static void bmp_contrast_adjust(WILLUSBITMAP *dest,WILLUSBITMAP *src,double contrast)

    {
    int i;
    static unsigned char newval[256];

    for (i=0;i<256;i++)
        {
        double x,y;
        int sgn,v;
        x=(i-127.5)/127.5;
        sgn = x<0 ? -1 : 1;
        if (contrast<0)
            sgn = -sgn;
        x=fabs(x);
        if (fabs(contrast)>1.5)
            y=x<.99999 ? 1-exp(fabs(contrast)*x/(x-1)) : 1.;
        else
            {
            y=fabs(contrast)*x;
            if (y>1.)
                y=1.;
            }
        y = 127.5+y*sgn*127.5;
        v = (int)(y+.5);
        if (v<0)
            v=0;
        if (v>255)
            v=255;
        newval[i] = v;
        }
    bmp_color_xform(dest,src,newval);
    }

/*
 ** Convert bitmap to grey-scale in-situ
 */
static void bmp_convert_to_greyscale_ex(WILLUSBITMAP *dst, WILLUSBITMAP *src)

{
	int oldbpr, newbpr, bpp, dp, rownum, colnum, i;

	oldbpr = bmp_bytewidth(src);
	dp = src->bpp == 8 ? 1 : 3;
	bpp = src->bpp;
	dst->bpp = 8;
	for (i = 0; i < 256; i++)
		dst->red[i] = dst->green[i] = dst->blue[i] = i;
	if (dst != src) {
		dst->width = src->width;
		dst->height = src->height;
		bmp_alloc(dst);
	}
	newbpr = bmp_bytewidth(dst);
	/* Possibly restore src->bpp to 24 so RGBGET works right (src & dst may be the same) */
	src->bpp = bpp;
	for (rownum = 0; rownum < src->height; rownum++) {
		unsigned char *oldp, *newp;
		oldp = &src->data[oldbpr * rownum];
		newp = &dst->data[newbpr * rownum];
		for (colnum = 0; colnum < src->width; colnum++, oldp += dp, newp++) {
			int r, g, b;
			RGBGET(src, oldp, r, g, b);
			(*newp) = bmp8_greylevel_convert(r, g, b);
		}
	}
	dst->bpp = 8; /* Possibly restore dst->bpp to 8 since src & dst may be the same. */
}

/* bmpmupdf.c */
static int bmpmupdf_pixmap_to_bmp(WILLUSBITMAP *bmp, fz_context *ctx,
		fz_pixmap *pixmap)

{
	unsigned char *p;
	int ncomp, i, row, col;

	bmp->width = fz_pixmap_width(ctx, pixmap);
	bmp->height = fz_pixmap_height(ctx, pixmap);
	ncomp = fz_pixmap_components(ctx, pixmap);
	/* Has to be 8-bit or RGB */
	if (ncomp != 2 && ncomp != 4)
		return (-1);
	bmp->bpp = (ncomp == 2) ? 8 : 24;
	bmp_alloc(bmp);
	if (ncomp == 2)
		for (i = 0; i < 256; i++)
			bmp->red[i] = bmp->green[i] = bmp->blue[i] = i;
	p = fz_pixmap_samples(ctx, pixmap);
	if (ncomp == 1)
		for (row = 0; row < bmp->height; row++) {
			unsigned char *dest;
			dest = bmp_rowptr_from_top(bmp, row);
			memcpy(dest, p, bmp->width);
			p += bmp->width;
		}
	else if (ncomp == 2)
		for (row = 0; row < bmp->height; row++) {
			unsigned char *dest;
			dest = bmp_rowptr_from_top(bmp, row);
			for (col = 0; col < bmp->width; col++, dest++, p += 2)
				dest[0] = p[0];
		}
	else
		for (row = 0; row < bmp->height; row++) {
			unsigned char *dest;
			dest = bmp_rowptr_from_top(bmp, row);
			for (col = 0; col < bmp->width;
					col++, dest += ncomp - 1, p += ncomp)
				memcpy(dest, p, ncomp - 1);
		}
	return (0);
}

static void handle(int wait, ddjvu_context_t *ctx)
    {
    const ddjvu_message_t *msg;

    if (!ctx)
        return;
    if (wait)
        msg = ddjvu_message_wait(ctx);
    while ((msg = ddjvu_message_peek(ctx)))
        {
        switch(msg->m_any.tag)
            {
            case DDJVU_ERROR:
                fprintf(stderr,"ddjvu: %s\n", msg->m_error.message);
                if (msg->m_error.filename)
                    fprintf(stderr,"ddjvu: '%s:%d'\n",
                      msg->m_error.filename, msg->m_error.lineno);
            exit(10);
            default:
            break;
            }
        }
    ddjvu_message_pop(ctx);
}

