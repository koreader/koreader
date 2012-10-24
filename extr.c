/*
    extr: Extract attachments from PDF file

	Usage: extr /dir/file.pdf pageno
	Returns 0 if one or more attachments saved, otherwise returns non-zero.
	Prints the number of saved attachments on stdout.
	Attachments are saved in /dir directory with the appropriate filenames.

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

#include "mupdf-internal.h"
#include <libgen.h>

static pdf_document *doc;

void dump_stream(int i, FILE *fout)
{
	fz_stream *stm = pdf_open_stream(doc, i, 0);
	static unsigned char buf[8192];
	while (1) {
		int n = fz_read(stm, buf, sizeof buf);
		if (n == 0) break;
		fwrite(buf, 1, n, fout);
	}
	fz_close(stm);
}

/* returns the number of attachments saved */
int save_attachments(int pageno, char *targetdir)
{
	pdf_page *page = pdf_load_page(doc, pageno-1);
	pdf_annot *annot;
	int saved_count = 0;

	for (annot = page->annots; annot ; annot = annot->next) {
		pdf_obj *fs_obj = pdf_dict_gets(annot->obj, "FS");
		if (fs_obj) {
			pdf_obj *ef_obj;
			char *name = basename(strdup(pdf_to_str_buf(pdf_dict_gets(fs_obj, "F"))));
			ef_obj = pdf_dict_gets(fs_obj, "EF");
			if (ef_obj) {
				pdf_obj *f_obj = pdf_dict_gets(ef_obj, "F");
				if (f_obj && pdf_is_indirect(f_obj)) {
					static char pathname[PATH_MAX];
					sprintf(pathname, "%s/%s", targetdir, name);
					FILE *fout = fopen(pathname, "w");
					if (!fout) {
						fprintf(stderr, "extr: cannot write to file %s\n", name);
						exit(1);
					}
					dump_stream(pdf_to_num(f_obj), fout);
					fclose(fout);
					saved_count++;
				}
			}
		}
	}
	return saved_count;
}

int main(int argc, char *argv[])
{
	int saved = 0;

	if (argc != 3) {
		printf("Usage: extr file.pdf pageno\n");
		exit(1);
	}

	char *filename = strdup(argv[1]);
	char *dir = dirname(strdup(filename));
	int pageno = atoi(argv[2]);

	fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
	if (!ctx) {
		fprintf(stderr, "extr: cannot create context\n");
		exit(1);
	}

	fz_var(doc);
	fz_try(ctx) {
		doc = pdf_open_document(ctx, filename);
		saved = save_attachments(pageno, dir);
	}
	fz_catch(ctx)
	{
	}

	printf("%d\n", saved);
	return 0;
}
