
CC = cc

CFLAG = -g -O 
LIBS = -lNeXT_s -lFoundation_s -lDriver 

pasteboard_daemon:	pasteboard_daemon.o jconv.o
	$(CC) -o pasteboard_daemon pasteboard_daemon.o jconv.o $(LIBS)

pasteboard_daemon.o: pasteboard_daemon.m
	$(CC) $(CFLAGS) -c pasteboard_daemon.m 

jconv.o: jconv.c jconv.h
	$(CC) $(CFLAGS) -c jconv.c

clean:
	rm pasteboard_daemon  pasteboard_daemon.o jconv.o

