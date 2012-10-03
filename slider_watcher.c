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

#include "popen-noshell/popen_noshell.h"
#include <err.h>
#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <sys/wait.h>

#define CODE_IN_SAVER 10000
#define CODE_OUT_SAVER 10001

int
main ( int argc, char *argv[] )
{
	int fd;
	FILE *fp;
	char std_out[256];
	int status;
	struct popen_noshell_pass_to_pclose pclose_arg;
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
		printf("Open %s failed: %s\n", argv[1], strerror(errno));
		exit(EXIT_FAILURE);
	}

	/* initialize event struct */
	ev.type = EV_KEY;
	ev.code = key_code;
	ev.value = 1;

	/* listen power slider events */
	char *argv[] = {"lipc-wait-event", "-m", "-s", "0", "com.lab126.powerd", "goingToScreenSaver,outOfScreenSaver", (char *) NULL};

	fp = popen_noshell("lipc-wait-event", (const char * const *)chargv, "r", &pclose_arg, 0);
	if (!fp) {
		err(EXIT_FAILURE, "popen_noshell()");
	}

	while(fgets(std_out, sizeof(std_out)-1, fp)) {

		/* printf("Got line: %s", std_out); */

		if(std_out[0] == 'g') {
			ev.code = CODE_IN_SAVER;
		} else if(std_out[0] == 'o') {
			ev.code = CODE_OUT_SAVER;
		} else {
			printf("Unrecognized event.\n");
			exit(EXIT_FAILURE);
		}
		/* fill event struct */
		gettimeofday(&ev.time, NULL);

		/* printf("Send event %d\n", ev.code); */

		/* generate event */
		if(write(fd, &ev, sizeof(struct input_event)) == -1) {
			printf("Failed to generate event.\n");
		}
	}

	status = pclose_noshell(&pclose_arg);
	if (status == -1) {
		err(EXIT_FAILURE, "pclose_noshell()");
	} else {
		printf("Power slider event listener child exited with status %d.\n", status);

		if WIFEXITED(status) {
			printf("Child exited normally with status: %d.\n", WEXITSTATUS(status));
		}
		if WIFSIGNALED(status) {
			printf("Child terminated by signal: %d.\n", WTERMSIG(status));
		}
	}

	close(fd);
	return EXIT_SUCCESS;
}
