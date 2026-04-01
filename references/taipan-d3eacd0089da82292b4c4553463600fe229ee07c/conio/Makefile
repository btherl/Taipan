all: conio.lib

OBJS=cgetc.o chline.o cputc.o cputs.o cvline.o

# unused, disabled:
# clrscr.o gotox.o gotoxy.o gotoy.o wherex.o wherey.o revers.o

conio.lib: $(OBJS)
	ar65 a conio.lib *.o

.s.o:
	cl65 -O -t atari -c $<

clean:
	rm -f *.o
