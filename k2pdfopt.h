/*
 ** k2pdfopt.h   K2pdfopt optimizes PDF/DJVU files for mobile e-readers
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
 */

#ifndef _K2PDFOPT_H
#define _K2PDFOPT_H

#include <fitz/fitz-internal.h>
#include <libdjvu/ddjvuapi.h>

typedef unsigned char  uint8_t;
typedef struct KOPTContext {
	int trim;
	int wrap;
	int indent;
	int rotate;
	int columns;
	int offset_x;
	int offset_y;
	int dev_width;
	int dev_height;
	int page_width;
	int page_height;
	int straighten;
	int justification;

	double zoom;
	double margin;
	double quality;
	double contrast;
	double defect_size;
	double line_spacing;
	double word_spacing;

	uint8_t *data;
} KOPTContext;

void k2pdfopt_mupdf_reflow(KOPTContext *kc, fz_document *doc, fz_page *page, fz_context *ctx);
void k2pdfopt_djvu_reflow(KOPTContext *kc, ddjvu_page_t *page, ddjvu_context_t *ctx, ddjvu_render_mode_t mode, ddjvu_format_t *fmt);

#endif

