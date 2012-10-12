/*
    KindlePDFViewer: JPEG support for Picture Viewer module
    Copyright (C) 2012 Tigran Aivazian <tigran@bibles.org.uk>

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

#include <stdint.h>
#include <string.h>
#include <setjmp.h>
#include <stdio.h>

#include "jpeglib.h"

struct my_error_mgr {
	struct jpeg_error_mgr pub;
	jmp_buf setjmp_buffer;
};

typedef struct my_error_mgr *my_error_ptr;

METHODDEF(void) my_error_exit(j_common_ptr cinfo)
{
	my_error_ptr myerr = (my_error_ptr) cinfo->err;
	(*cinfo->err->output_message) (cinfo);
	longjmp(myerr->setjmp_buffer, 1);
}

uint8_t *jpegLoadFile(const char *fname, int *width, int *height, int *components)
{
	struct jpeg_decompress_struct cinfo;
	struct my_error_mgr jerr;
	FILE *infile;
	JSAMPARRAY buffer;
	int row_stride;
	long cont;
	JSAMPLE *image_buffer;

	if ((infile = fopen(fname, "r")) == NULL) return NULL;
	cinfo.err = jpeg_std_error(&jerr.pub);
	jerr.pub.error_exit = my_error_exit;
	if (setjmp(jerr.setjmp_buffer)) {
		jpeg_destroy_decompress(&cinfo);
		fclose(infile);
		return NULL;
	}
	jpeg_create_decompress(&cinfo);
	jpeg_stdio_src(&cinfo, infile);
	(void) jpeg_read_header(&cinfo, TRUE);
	(void) jpeg_start_decompress(&cinfo);
	row_stride = cinfo.output_width * cinfo.output_components;
	buffer = (*cinfo.mem->alloc_sarray)
		((j_common_ptr) & cinfo, JPOOL_IMAGE, row_stride, 1);

	image_buffer = (JSAMPLE *) malloc(cinfo.image_width*cinfo.image_height*cinfo.output_components);
	if (image_buffer == NULL) return NULL;
	*width = cinfo.image_width;
	*height = cinfo.image_height;

	//cont = cinfo.output_height - 1;
	cont = 0;
	while (cinfo.output_scanline < cinfo.output_height) {
		(void) jpeg_read_scanlines(&cinfo, buffer, 1);
		memcpy(image_buffer + cinfo.image_width * cinfo.output_components * cont, buffer[0], row_stride);
		cont++;
	}

	(void) jpeg_finish_decompress(&cinfo);
	jpeg_destroy_decompress(&cinfo);
	fclose(infile);
	*components = cinfo.output_components;
	return (uint8_t *)image_buffer;
}
