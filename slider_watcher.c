/*
    KindlePDFViewer: power slider key event watcher
    Copyright (C) 2012 Qingping Hou <dave2008713@gamil.com>

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

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>

#define OUTPUT_SIZE 21
#define EVENT_PIPE "/tmp/event_slider"
#define CODE_IN_SAVER 10000
#define CODE_OUT_SAVER 10001

int
main ( int argc, char *argv[] )
{
	int fd, ret;
	FILE *fp;
	char std_out[OUTPUT_SIZE] = "";
	struct input_event ev;
	__u16 key_code = 10000;

	/* create the npipe if not exists */
	/*if(access(argv[1], F_OK)){*/
		/*printf("npipe %s not found, try to create it...\n", argv[1]);*/
		/*if(mkfifo(argv[1], 0777)) {*/
			/*printf("Create npipe %s failed!\n", argv[1]);*/
		/*}*/
	/*}*/

	/* open npipe for writing */
	fd = open(argv[1], O_RDWR | O_NONBLOCK);
	if(fd < 0) {
		printf("Open %s falied: %s\n", argv[1], strerror(errno));
		exit(EXIT_FAILURE);
	}

	/* initialize event struct */
	ev.type = EV_KEY;
	ev.code = key_code;
	ev.value = 1;

	while(1) {
		/* listen power slider events */
		memset(std_out, 0, OUTPUT_SIZE);
		fp = popen("lipc-wait-event  -s 0 com.lab126.powerd goingToScreenSaver,outOfScreenSaver", "r");
		ret = fread(std_out, OUTPUT_SIZE, 1, fp);
		pclose(fp);

		/* fill event struct */
		gettimeofday(&ev.time, NULL);
		if(std_out[0] == 'g') {
			ev.code = CODE_IN_SAVER;
		} else if(std_out[0] == 'o') {
			ev.code = CODE_OUT_SAVER;
		} else {
			printf("Unrecognized event.\n");
			exit(EXIT_FAILURE);
		}

		/* generate event */
		ret = write(fd, &ev, sizeof(struct input_event));
	}

	close(fd);
	return EXIT_SUCCESS;
}
