/*
	build as a 32K diagnostic cart:
	cl65 -m hello52.map -t atari5200 -Wl -D__CARTSIZE__=0x8000 -o 1.bin hello52.c cartname_5200.s cartyear_5200.s crt0_5200.s

	run with original OS:
	atari800 -5200 -cart-type 4 -cart 1.bin

	or run with rev A:
	atari800 -5200 -5200-rev a -cart-type 4 -cart 1.bin

*/

#include <conio.h>

int main(void) {
	gotoxy(5, 11);
	cputs("HELLO WORLD");
hang: goto hang;
	return 0;
}
