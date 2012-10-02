SRCS=popen_noshell.c

OBJS:=$(SRCS:%.c=%.o)

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ -c $<

all: libpopen_noshell.a

libpopen_noshell.a: $(OBJS)
	$(AR) rcs $@ $(OBJS)

clean:
	rm -rf *.o
	rm -rf libpopen_noshell.a