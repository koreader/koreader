/*
    KindlePDFViewer: Interface to JPEG module for picture viewer
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
#ifndef _PIC_JPEG_H
#define _PIC_JPEG_H

/* each new image format must provide fmtLoadFile() function which
 * performs the following:
 * 1. Opens the file 'filename'
 * 2. Reads the image data from it into a buffer allocated with malloc()
 * 3. Fills in the image *width, *height and *components (number of bytes per pixel)
 * 4. Closes the file
 * 5. Returns the pointer to the image data
 */
extern uint8_t *jpegLoadFile(const char *fname, int *width, int *height, int *components);
#endif
