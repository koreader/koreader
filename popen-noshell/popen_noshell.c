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

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "popen_noshell.h"
#include <errno.h>
#include <unistd.h>
#include <err.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <inttypes.h>
#include <sched.h>

/*
 * Wish-list:
 *	1) Make the "ignore_stderr" parameter a mode - ignore, leave unchanged, redirect to stdout (the last is not implemented yet)
 *	2) Code a faster system(): system_noshell(), system_noshell_compat()
 */

//#define POPEN_NOSHELL_DEBUG

// because of C++, we can't call err() or errx() within the child, because they call exit(), and _exit() is what must be called; so we wrap
#define _ERR(EVAL, FMT, ...) \
	{ \
		warn(FMT, ##__VA_ARGS__); \
		_exit(EVAL); \
	}
#define _ERRX(EVAL, FMT, ...) \
	{ \
		warnx(FMT, ##__VA_ARGS__); \
		_exit(EVAL); \
	}

int _popen_noshell_fork_mode = POPEN_NOSHELL_MODE_CLONE;

void popen_noshell_set_fork_mode(int mode) { // see "popen_noshell.h" POPEN_NOSHELL_MODE_* constants
	_popen_noshell_fork_mode = mode;
}

int popen_noshell_reopen_fd_to_dev_null(int fd) {
	int dev_null_fd;

	dev_null_fd = open("/dev/null", O_RDWR);
	if (dev_null_fd < 0) return -1;

	if (close(fd) != 0) {
		return -1;
	}
	if (dup2(dev_null_fd, fd) == -1) {
		return -1;
	}
	if (close(dev_null_fd) != 0) {
		return -1;
	}

	return 0;
}

int _popen_noshell_close_and_dup(int pipefd[2], int closed_pipefd, int target_fd) {
	int dupped_pipefd;

	dupped_pipefd = (closed_pipefd == 0 ? 1 : 0); // get the FD of the other end of the pipe

	if (close(pipefd[closed_pipefd]) != 0) {
		return -1;
	}

	if (close(target_fd) != 0) {
		return -1;
	}
	if (dup2(pipefd[dupped_pipefd], target_fd) == -1) {
		return -1;
	}
	if (close(pipefd[dupped_pipefd]) != 0) {
		return -1;
	}

	return 0;
}

void _pclose_noshell_free_clone_arg_memory(struct popen_noshell_clone_arg *func_args) {
	char **cmd_argv;

	free((char *)func_args->file);
	cmd_argv = (char **)func_args->argv;
	while (*cmd_argv) {
		free(*cmd_argv);
		++cmd_argv;
	}
	free((char **)func_args->argv);
	free(func_args);
}

void _popen_noshell_child_process(
	/* We need the pointer *arg_ptr only to free whatever we reference if exec() fails and we were fork()'ed (thus memory was copied),
	 * not clone()'d */
	struct popen_noshell_clone_arg *arg_ptr, /* NULL if we were called by pure fork() (not because of Valgrind) */
	int pipefd_0, int pipefd_1, int read_pipe, int ignore_stderr, const char *file, const char * const *argv) {

	int closed_child_fd;
	int closed_pipe_fd;
	int dupped_child_fd;
	int pipefd[2] = {pipefd_0, pipefd_1};

	if (ignore_stderr) { /* ignore STDERR completely? */
		if (popen_noshell_reopen_fd_to_dev_null(STDERR_FILENO) != 0) _ERR(255, "popen_noshell_reopen_fd_to_dev_null(%d)", STDERR_FILENO);
	}

	if (read_pipe) {
		closed_child_fd = STDIN_FILENO;		/* re-open STDIN to /dev/null */
		closed_pipe_fd = 0;			/* close read end of pipe */
		dupped_child_fd = STDOUT_FILENO;	/* dup the other pipe end to STDOUT */
	} else {
		closed_child_fd = STDOUT_FILENO;	/* ignore STDOUT completely */
		closed_pipe_fd = 1;			/* close write end of pipe */
		dupped_child_fd = STDIN_FILENO;		/* dup the other pipe end to STDIN */
	}
	if (popen_noshell_reopen_fd_to_dev_null(closed_child_fd) != 0) {
		_ERR(255, "popen_noshell_reopen_fd_to_dev_null(%d)", closed_child_fd);
	}
	if (_popen_noshell_close_and_dup(pipefd, closed_pipe_fd, dupped_child_fd) != 0) {
		_ERR(255, "_popen_noshell_close_and_dup(%d ,%d)", closed_pipe_fd, dupped_child_fd);
	}

	execvp(file, (char * const *)argv);

	/* if we are here, exec() failed */

	warn("exec(\"%s\") inside the child", file);

#ifdef POPEN_NOSHELL_VALGRIND_DEBUG
	if (arg_ptr) { /* not NULL if we were called by clone() */
		/* but Valgrind does not support clone(), so we were actually called by fork(), thus memory was copied... */
		/* free this copied memory; if it was not Valgrind, this memory would have been shared and would belong to the parent! */
		_pclose_noshell_free_clone_arg_memory(arg_ptr);
	}
#endif

	if (fflush(stdout) != 0) _ERR(255, "fflush(stdout)");
	if (fflush(stderr) != 0) _ERR(255, "fflush(stderr)");
	close(STDIN_FILENO);
	close(STDOUT_FILENO);
	close(STDERR_FILENO);

	_exit(255); // call _exit() and not exit(), or you'll have troubles in C++
}

int popen_noshell_child_process_by_clone(void *raw_arg) {
	struct popen_noshell_clone_arg *arg;

	arg = (struct popen_noshell_clone_arg *)raw_arg;
	_popen_noshell_child_process(arg, arg->pipefd_0, arg->pipefd_1, arg->read_pipe, arg->ignore_stderr, arg->file, arg->argv);

	return 0;
}

char ** popen_noshell_copy_argv(const char * const *argv_orig) {
	int size = 1; /* there is at least one NULL element */
	char **argv;
	char **argv_new;
	int n;

	argv = (char **) argv_orig;
	while (*argv) {
		++size;
		++argv;
	}

	argv_new = (char **)malloc(sizeof(char *) * size);
	if (!argv_new) return NULL;

	argv = (char **)argv_orig;
	n = 0;
	while (*argv) {
		argv_new[n] = strdup(*argv);
		if (!argv_new[n]) return NULL;
		++argv;
		++n;
	}
	argv_new[n] = (char *)NULL;

	return argv_new;
}

/*
 * Similar to vfork() and threading.
 * Starts a process which behaves like a thread (shares global variables in memory with the parent) but
 * has a different PID and can call exec(), unlike traditional threads which are not allowed to call exec().
 *
 * This fork function is very resource-light because it does not copy any memory from the parent, but shares it.
 *
 * Like standard threads, you have to provide a start function *fn and arguments to it *arg. The life of the
 * new vmfork()'ed process starts from this function.
 *
 * After you have reaped the child via waitpid(), you have to free() the memory at "*memory_to_free_on_child_exit".
 *
 * When the *fn function returns, the child process terminates.  The integer returned by *fn is the exit code for the child process.
 * The child process may also terminate explicitly by calling exit(2) or after receiving a fatal signal.
 *
 * Returns -1 on error. On success returns the PID of the newly created child.
 */
pid_t popen_noshell_vmfork(int (*fn)(void *), void *arg, void **memory_to_free_on_child_exit) {
		void *stack, *stack_aligned;
		pid_t pid;

		stack = malloc(POPEN_NOSHELL_STACK_SIZE + 15);
		if (!stack) return -1;
		*memory_to_free_on_child_exit = stack;

		/*
		 * On all supported Linux platforms the stack grows down, except for HP-PARISC.
		 * You can grep the kernel source for "STACK_GROWSUP", in order to get this information.
		 */
		// stack grows down, set pointer at the end of the block
		stack_aligned = (void *) ((char * /*byte*/)stack + POPEN_NOSHELL_STACK_SIZE/*bytes*/);

		/*
		 * On all supported platforms by GNU libc, the stack is aligned to 16 bytes, except for the SuperH platform which is aligned to 8 bytes.
		 * You can grep the glibc source for "STACK_ALIGN", in order to get this information.
		 */
		stack_aligned = (void *) ( ((uintptr_t)stack_aligned+15) & ~ 0x0F ); // align to 16 bytes

		/*
		 * Maybe we could have used posix_memalign() here...
		 * Our implementation seems a bit more portable though - I've read somewhere that posix_memalign() is not supported on all platforms.
		 * The above malloc() + align implementation is taken from:
		 * 	http://stackoverflow.com/questions/227897/solve-the-memory-alignment-in-c-interview-question-that-stumped-me
		 */

#ifndef POPEN_NOSHELL_VALGRIND_DEBUG
		pid = clone(fn, stack_aligned, CLONE_VM | SIGCHLD, arg);
#else
		pid = fork(); // Valgrind does not support arbitrary clone() calls, so we use fork for the tests
#endif
		if (pid == -1) return -1;

		if (pid == 0) { // child
#ifdef POPEN_NOSHELL_VALGRIND_DEBUG
			free(stack); // this is a copy because of the fork(), we are not using it at all
			_exit(fn(arg)); // if we used fork() because of Valgrind, invoke the child function manually; always use _exit()
#endif
			errx(EXIT_FAILURE, "This must never happen");
		} // child life ends here, for sure

		return pid;
}

/*
 * Pipe stream to or from process. Similar to popen(), only much faster.
 *
 * "file" is the command to be executed. It is searched within the PATH environment variable.
 * "argv[]" is an array to "char *" elements which are passed as command-line arguments.
 *	Note: The first element must be the same string as "file".
 *	Note: The last element must be a (char *)NULL terminating element.
 * "type" specifies if we are reading from the STDOUT or writing to the STDIN of the executed command "file". Use "r" for reading, "w" for writing.
 * "pid" is a pointer to an interger. The PID of the child process is stored there.
 * "ignore_stderr" has the following meaning:
 *	0: leave STDERR of the child process attached to the current STDERR of the parent process
 * 	1: ignore the STDERR of the child process
 *
 * This function is not very sustainable on failures. This means that if it fails for some reason (out of memory, no such executable, etc.),
 * you are probably in trouble, because the function allocated some memory or file descriptors and never released them.
 * Normally, this function should never fail.
 *
 * Returns NULL on any error, "errno" is set appropriately.
 * On success, a stream pointer is returned.
 * 	When you are done working with the stream, you have to close it by calling pclose_noshell(), or else you will leave zombie processes.
 */
FILE *popen_noshell(const char *file, const char * const *argv, const char *type, struct popen_noshell_pass_to_pclose *pclose_arg, int ignore_stderr) {
	int read_pipe;
	int pipefd[2]; // 0 -> READ, 1 -> WRITE ends
	pid_t pid;
	FILE *fp;

	memset(pclose_arg, 0, sizeof(struct popen_noshell_pass_to_pclose));

	if (strcmp(type, "r") == 0) {
		read_pipe = 1;
	} else if (strcmp(type, "w") == 0) {
		read_pipe = 0;
	} else {
		errno = EINVAL;
		return NULL;
	}

	if (pipe(pipefd) != 0) return NULL;

	if (_popen_noshell_fork_mode) { // use fork()

		pid = fork();
		if (pid == -1) return NULL;
		if (pid == 0) {
			_popen_noshell_child_process(NULL, pipefd[0], pipefd[1], read_pipe, ignore_stderr, file, argv);
			errx(EXIT_FAILURE, "This must never happen");
		} // child life ends here, for sure

	} else { // use clone()

		struct popen_noshell_clone_arg *arg = NULL;

		arg = (struct popen_noshell_clone_arg*) malloc(sizeof(struct popen_noshell_clone_arg));
		if (!arg) return NULL;

		/* Copy memory structures, so that nobody can free() our memory while we use it in the child! */
		arg->pipefd_0 = pipefd[0];
		arg->pipefd_1 = pipefd[1];
		arg->read_pipe = read_pipe;
		arg->ignore_stderr = ignore_stderr;
		arg->file = strdup(file);
		if (!arg->file) return NULL;
		arg->argv = (const char * const *)popen_noshell_copy_argv(argv);
		if (!arg->argv) return NULL;

		pclose_arg->free_clone_mem = 1;
		pclose_arg->func_args = arg;
		pclose_arg->stack = NULL; // we will populate it below

		pid = popen_noshell_vmfork(&popen_noshell_child_process_by_clone, arg, &(pclose_arg->stack));
		if (pid == -1) return NULL;

	} // done: using clone()

	/* parent process */

	if (read_pipe) {
		if (close(pipefd[1/*write*/]) != 0) return NULL;
		fp = fdopen(pipefd[0/*read*/], "r");
	} else { // write_pipe
		if (close(pipefd[0/*read*/]) != 0) return NULL;
		fp = fdopen(pipefd[1/*write*/], "w");
	}
	if (fp == NULL) {
		return NULL; // fdopen() failed
	}

	pclose_arg->fp = fp;
	pclose_arg->pid = pid;

	return fp; // we should never end up here
}

int popen_noshell_add_ptr_to_argv(char ***argv, int *count, char *start) {
		*count += 1;
		*argv = (char **) realloc(*argv, *count * sizeof(char **));
		if (*argv == NULL) {
			return -1;
		}
		*(*argv + *count - 1) = start;
		return 0;
}

int _popen_noshell_add_token(char ***argv, int *count, char *start, char *command, int *j) {
	if (start != NULL && command + *j - 1 - start >= 0) {
		command[*j] = '\0'; // terminate the token in memory
		*j += 1;
#ifdef POPEN_NOSHELL_DEBUG
		printf("Token: %s\n", start);
#endif
		if (popen_noshell_add_ptr_to_argv(argv, count, start) != 0) {
			return -1;
		}
	}
	return 0;
}

#define _popen_noshell_split_return_NULL { if (argv != NULL) free(argv); if (command != NULL) free(command); return NULL; }
char ** popen_noshell_split_command_to_argv(const char *command_original, char **free_this_buf) {
	char *command;
	size_t i, len;
	char *start = NULL;
	char c;
	char **argv = NULL;
	int count = 0;
	const char _popen_bash_meta_characters[] = "!\\$`\n|&;()<>";
	int in_sq = 0;
	int in_dq = 0;
	int j = 0;
#ifdef POPEN_NOSHELL_DEBUG
	char **tmp;
#endif

	command = (char *)calloc(strlen(command_original) + 1, sizeof(char));
	if (!command) _popen_noshell_split_return_NULL;

	*free_this_buf = command;

	len = strlen(command_original); // get the original length
	j = 0;
	for (i = 0; i < len; ++i) {
		if (!start) start = command + j;
		c = command_original[i];

		if (index(_popen_bash_meta_characters, c) != NULL) {
			errno = EINVAL;
			_popen_noshell_split_return_NULL;
		}

		if (c == ' ' || c == '\t') {
			if (in_sq || in_dq) {
				command[j++] = c;
				continue;
			}

			// new token
			if (_popen_noshell_add_token(&argv, &count, start, command, &j) != 0) {
				_popen_noshell_split_return_NULL;
			}
			start = NULL;
			continue;
		}

		if (c == '\'' && !in_dq) {
			in_sq = !in_sq;
			continue;
		}
		if (c == '"' && !in_sq) {
			in_dq = !in_dq;
			continue;
		}

		command[j++] = c;
	}
	if (in_sq || in_dq) { // unmatched single/double quote
		errno = EINVAL;
		_popen_noshell_split_return_NULL;
	}

	if (_popen_noshell_add_token(&argv, &count, start, command, &j) != 0) {
		_popen_noshell_split_return_NULL;
	}

	if (count == 0) {
		errno = EINVAL;
		_popen_noshell_split_return_NULL;
	}

	if (popen_noshell_add_ptr_to_argv(&argv, &count, NULL) != 0) { // NULL-terminate the list
		_popen_noshell_split_return_NULL;
	}

#ifdef POPEN_NOSHELL_DEBUG
	tmp = argv;
	while (*tmp) {
		printf("ARGV: |%s|\n", *tmp);
		++tmp;
	}
#endif

	return argv;

	/* Example test strings:
		"a'zz bb edd"
		" abc ff  "
		" abc ff"
		"' abc   ff  ' "
		""
		"     "
		"     '"
		"ab\\c"
		"ls -la /proc/self/fd 'z'  'ab'g'z\" zz'   \" abc'd\" ' ab\"c   def '"
	*/
}

/*
 * Pipe stream to or from process. Similar to popen(), only much faster.
 *
 * This is simpler than popen_noshell() but is more INSECURE.
 * Since shells have very complicated expansion, quoting and word splitting algorithms, we do NOT try to re-implement them here.
 * This function does NOT support any special characters. It will immediately return an error if such symbols are encountered in "command".
 * The "command" is split only by space and tab delimiters. The special symbols are pre-defined in _popen_bash_meta_characters[].
 * The only special characters supported are single and double quotes. You can enclose arguments in quotes and they should be splitted correctly.
 *
 * If possible, use popen_noshell() because of its better security.
 *
 * "command" is the command and its arguments to be executed. The command is searched within the PATH environment variable.
 *	The whole "command" string is parsed and splitted, so that it can be directly given to popen_noshell() and resp. to exec().
 *	This parsing is very simple and may contain bugs (see above). If possible, use popen_noshell() directly.
 * "type" specifies if we are reading from the STDOUT or writing to the STDIN of the executed command. Use "r" for reading, "w" for writing.
 * "pid" is a pointer to an interger. The PID of the child process is stored there.
 *
 * Returns NULL on any error, "errno" is set appropriately.
 * On success, a stream pointer is returned.
 * 	When you are done working with the stream, you have to close it by calling pclose_noshell(), or else you will leave zombie processes.
 */
FILE *popen_noshell_compat(const char *command, const char *type, struct popen_noshell_pass_to_pclose *pclose_arg) {
	char **argv;
	FILE *fp;
	char *to_free;

	argv = popen_noshell_split_command_to_argv(command, &to_free);
	if (!argv) {
		if (to_free) free(to_free);
		return NULL;
	}

	fp = popen_noshell(argv[0], (const char * const *)argv, type, pclose_arg, 0);

	free(to_free);
	free(argv);

	return fp;
}

/*
 * You have to call this function after you have done working with the FILE pointer "fp" returned by popen_noshell() or by popen_noshell_compat().
 *
 * Returns -1 on any error, "errno" is set appropriately.
 * Returns the "status" of the child process as returned by waitpid().
 */
int pclose_noshell(struct popen_noshell_pass_to_pclose *arg) {
	int status;

	if (fclose(arg->fp) != 0) {
		return -1;
	}

	if (waitpid(arg->pid, &status, 0) != arg->pid) {
		return -1;
	}

	if (arg->free_clone_mem) {
		free(arg->stack);
		_pclose_noshell_free_clone_arg_memory(arg->func_args);
	}

	return status;
}
