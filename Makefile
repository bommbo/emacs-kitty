CC = gcc
CFLAGS = -fPIC -Wall -I/usr/include
LDFLAGS = -shared

terminal-query.so: emacs-terminal-query.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o terminal-query.so emacs-terminal-query.c

clean:
	rm -f terminal-query.so

.PHONY: clean
