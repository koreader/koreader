/*
 * popen_noshell: A faster implementation of popen() and system() for Linux.
 * Copyright (c) 2009 Ivan Zahariev (famzah)
 * Version: 1.0
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; under version 3 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses>.
 */

#ifndef POPEN_NOSHELL_H
#define POPEN_NOSHELL_H

#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

/* stack for the child process before it does exec() */
#define POPEN_NOSHELL_STACK_SIZE 8*1024*1024 /* currently most Linux distros set this to 8 MBytes */

/* constants to use with popen_noshell_set_fork_mode() */
#define POPEN_NOSHELL_MODE_CLONE 0 /* default, faster */
#define POPEN_NOSHELL_MODE_FORK 1 /* slower */

struct popen_noshell_clone_arg {
	int pipefd_0;
	int pipefd_1;
	int read_pipe;
	int ignore_stderr;
	const char *file;
	const char * const *argv;
};

struct popen_noshell_pass_to_pclose {
	FILE *fp;
	pid_t pid;
	int free_clone_mem;
	void *stack;
	struct popen_noshell_clone_arg *func_args;
};

/***************************
 * PUBLIC FUNCTIONS FOLLOW *
 ***************************/

/* this is the native function call */
FILE *popen_noshell(const char *file, const char * const *argv, const char *type, struct popen_noshell_pass_to_pclose *pclose_arg, int ignore_stderr);

/* more insecure, but more compatible with popen() */
FILE *popen_noshell_compat(const char *command, const char *type, struct popen_noshell_pass_to_pclose *pclose_arg);

/* call this when you have finished reading and writing from/to the child process */
int pclose_noshell(struct popen_noshell_pass_to_pclose *arg); /* the pclose() equivalent */

/* this is the innovative faster vmfork() which shares memory with the parent and is very resource-light; see the source code for documentation */
pid_t popen_noshell_vmfork(int (*fn)(void *), void *arg, void **memory_to_free_on_child_exit);

/* used only for benchmarking purposes */
void popen_noshell_set_fork_mode(int mode);

#endif
