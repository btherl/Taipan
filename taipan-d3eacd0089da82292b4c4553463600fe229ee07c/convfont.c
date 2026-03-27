#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#include <unistd.h>
#include <stdio.h>

/* convfont - convert and combine the Atari ROM font and the
	Apple II Taipan font for use with Atari Taipan.

	Usage:

	# Extract the 1K Atari ROM font:
	dd if=atariosb.rom of=romfont bs=256 skip=8 count=4

	# Extract the Apple II Taipan font:
	dd if=taipan.dsk of=font bs=256 skip=54 count=3

	# Create the Atari 8-bit Taipan font as raw data:
	cat romfont font | ./convfont > taifont.raw

	# Or, create the Atari 8-bit Taipan font as a binary load,
	# with load address set to FONT_ADDR. This has to be defined
	# on the gcc command line when convfont is built (see Makefile):

	cat romfont font | ./convfont -x > taifont.xex

	In addition to writing the font on stdout, this program
	also creates LORCHA.DAT and DAMAGED.DAT. If they already
	exist, they are overwritten.

	There is NO error checking in this program! It expects exactly
	1792 bytes on its stdin (as in the commands above).
 */

/* Long-winded explanation of shipdata[] and how to edit it:

	Custom characters for ship graphics. 1st byte
	is screencode, the other 8 are the pixel data. The
	screencodes aren't in any particular order. They
	match the screencodes in shipshape[] and damaged_shipshape[].

	This stuff was originally done with a perl script that
	sliced up a PNG image of the lorcha, from an Apple II
	emulator screenshot. The script is long gone (it's from
	before I started using git for this project). At this
	point, nobody should ever have to edit the graphics again.
	I document the process I used, below, in case that turns
	out to be incorrect.

	Editing the ship graphics is a cumbersome mostly-manual
	process. Basically you copy the pixel data (8 hex pairs, do
	NOT copy the screencode too), and paste
	it into the stdin of hex2block.pl. If you wanted to edit
	the small flag on top of the right-hand sail:

	1. Locate its character code by looking at shipshape[]. It's
		the rightmost character on the 2nd row, 0x53.
	2. Find the shipdata[] line that begins with 0x53.
	3. Copy *just* the pixel data (don't copy the 0x53).
	4. Run this:

$ perl hex2block.pl > x.txt

	5. Paste your line of hex data in the terminal and press Enter.
	x.txt ends up looking like e.g.:

$ cat -A x.txt 
        $
        $
 X      $
 XXX    $
 XXXXX  $
 X   XXX$
 X      $
 X      $

	The $ are EOL markers put there by 'cat -A', so you can see
	the trailing spaces. You can see the flag shape made of X's.

	6. Edit x.txt with your favorite text editor, using X and space
		for lit/unlit pixels. There should be exactly 8 lines of 8
		characters (each of which is an X or a space).

	7. Run this:

$ perl block2hex.pl x.txt

	...which gives you hex data to paste into this file, e.g.:

0x00, 0x00, 0x40, 0x70, 0x7c, 0x47, 0x40, 0x40

	8. Copy the hex data, and paste it back into this file, replacing
		the original data for character 0x53.

	As you can see, I *really* should have written an easier to use
	tool for this. However, it might have taken me longer to do that
	than it did to just grind through all the damaged-ship graphics.

	Notes:

	Screen codes 0x41, 0x43, 0x44, 0x45, 0x51, 0x52, 0x5a are box
	drawing chars, used to draw the port status, firm naming, and
	retirement screens. So don't try to use them as ship pieces!

	0x54 is the ^T ball character, copied from the Atari ROM font.
	It looks OK as a hole made by a cannonball so I used it as-is
	(or actually, used 0xd4, the inverse video version).

	All the other graphics characters are used, plus a few printable
	ones (left/right square brackets, underscore).

	When you're editing the ship graphics, uncomment the
	#define LORCHA_TEST line near the top of taipan.c to see you
	work in progress (wail on the space bar to repeatedly damage
	the ships).

	If you want ASCII art versions of the healthy and fully-damaged
	lorcha, use "make lorcha.txt" and/or "make damaged.txt".
 */

char shipdata[][9] = {
	/* healthy ship blocks */
	{0x42 , 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x3f}, // ^B
	{0x4e , 0x18, 0x1f, 0x1f, 0x10, 0x10, 0x10, 0xff, 0xff}, // ^N
	{0x4f , 0x00, 0xf0, 0xfc, 0x3e, 0x00, 0x00, 0xfc, 0xf0}, // ^O
	{0x53 , 0x00, 0x00, 0x40, 0x70, 0x7c, 0x47, 0x40, 0x40}, // ^S
	{0x55 , 0x1f, 0x3f, 0xff, 0x3f, 0x1f, 0x3f, 0xff, 0x7f}, // ^U
	{0x56 , 0xc0, 0xf0, 0xfc, 0xf0, 0xc0, 0xf0, 0xfc, 0xf0}, // ^V
	{0x57 , 0x07, 0x03, 0x07, 0x0f, 0x07, 0x03, 0x07, 0x0f}, // ^W
	{0x58 , 0xfe, 0xfc, 0xfe, 0xff, 0xfe, 0xf8, 0xfe, 0xff}, // ^X
	{0x5b , 0xfe, 0xf8, 0xfe, 0xff, 0xfe, 0xfe, 0xfd, 0xf9}, // Esc symbol
	{0x3b , 0xc0, 0xfe, 0xff, 0xff, 0xff, 0xff, 0x7f, 0x1f}, // [
	{0x59 , 0x00, 0x00, 0xc0, 0xff, 0x8f, 0x8e, 0x8e, 0xfe}, // ^Y
	{0x3d , 0x38, 0x38, 0x38, 0x38, 0xff, 0x38, 0x38, 0x38}, // ]
	{0x5c , 0x00, 0x00, 0x00, 0x01, 0xff, 0xe3, 0xe3, 0xe3}, // up arrow
	{0x3f , 0x00, 0x00, 0x00, 0xff, 0x8e, 0x8e, 0x8e, 0xff}, // _
	{0x40 , 0xc3, 0xcf, 0xff, 0xff, 0x3f, 0x3e, 0x3c, 0xf8}, // heart (null)
	{0x46 , 0x1f, 0x0f, 0x07, 0x07, 0x07, 0x03, 0x03, 0x03}, // ^F
	{0x47 , 0xf0, 0xe0, 0xc0, 0xc0, 0xc0, 0xc0, 0x80, 0x80}, // ^G

	/* damaged ship blocks */
	{ 0x50 , 0x00, 0x00, 0x00, 0x00, 0x83, 0xc3, 0xe3, 0xe3}, // ^P
	{ 0x5d , 0xff, 0x9f, 0x8f, 0x9f, 0xf9, 0xf8, 0xf9, 0xff}, // down arrow
	{ 0x48 , 0x1f, 0x3b, 0xfd, 0x39, 0x18, 0x31, 0xfb, 0x7f}, // ^H
	{ 0x49 , 0xff, 0xff, 0xfd, 0xe1, 0x83, 0x0f, 0xff, 0xff}, // ^G
	{ 0x4a , 0xd5, 0xa3, 0x41, 0x81, 0x40, 0xb0, 0xfc, 0xff}, // ^I
	{ 0x4b , 0xc0, 0xf0, 0xfc, 0xf0, 0xc0, 0x00, 0x80, 0xf0}, // ^J
	{ 0x5e , 0x1f, 0x39, 0xf1, 0x39, 0x1f, 0x3c, 0xf8, 0x7c}, // L arrow
	{ 0x5f , 0xfe, 0xf8, 0xee, 0xcf, 0x9e, 0xbe, 0xfd, 0xf9}, // R arrow
	{ 0x60 , 0xfe, 0xbc, 0xc6, 0xcf, 0x96, 0xd8, 0xfe, 0xff}, // diamond
	{ 0x4c , 0xff, 0xff, 0xff, 0xff, 0xe8, 0x81, 0xe1, 0xff}, // ^L (UL 1/4 blk)
	{ 0x4d , 0xff, 0x8f, 0x8f, 0xe7, 0xfe, 0xf8, 0xf0, 0xff}, // ^M
	{ 0x7b , 0xfe, 0xf8, 0xbe, 0x97, 0x8e, 0xbe, 0xfc, 0xf8}, // spades
	{ 0x7d , 0xc0, 0xfe, 0xeb, 0xc7, 0xc3, 0xe7, 0x7f, 0x1f}, // clrscr (bent arrow)
	{ 0x7e , 0x00, 0x00, 0x00, 0x00, 0x80, 0xc1, 0xe3, 0xe3}, // left triangle
	{ 0x7f , 0xc3, 0xce, 0xf8, 0xf0, 0x30, 0x30, 0x3c, 0xfe}, // right triangle

	/* end of ship data marker */
	{ 0,    0,    0,    0,    0,    0,    0,    0,    0   }
};

/* This ends up in LORCHA.DAT, verbatim. See shipshape[] above
	for the definitions of each screencode used here. If you can't
	find a screencode in shipshape[], it's using the regular font
	character (e.g. 0x00 is a space, 0x80 is an inverse space
	aka solid 8x8 block). */
char shipshape[] = {
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x42, 0x4e, 0x4f, 0x00, 0x53,
	0x00, 0x00, 0x55, 0x80, 0x56, 0x57, 0x58,
	0x00, 0x00, 0x55, 0x80, 0x56, 0x57, 0x5b,
	0x00, 0x3b, 0x59, 0x3d, 0x5c, 0x3f, 0x40,
	0x00, 0x46, 0x80, 0x80, 0x80, 0x80, 0x47,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

/* DAMAGED.DAT - each time a lorcha gets damaged, a random
	character from here overwrites the original shipshape[]
	character in screen RAM. See draw_lorcha.s for details.
	If a part of the ship can't display damage, it'll have
	the same screencode here as it does in shipshape[]. */
char damaged_shipshape[] = {
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x42, 0x4e, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x5e, 0x4a, 0x56, 0x57, 0x60,
	0x00, 0x00, 0x48, 0xd4, 0x4b, 0x57, 0x5f,
	0x00, 0x7d, 0x7e, 0x7c, 0x7e, 0x50, 0x7f,
	0x00, 0x46, 0x4c, 0x5d, 0x4d, 0x49, 0x47,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

/* DAMAGED2.DAT - as above. damage_lorcha randomly picks
	from the 2 damaged ship shapes. */
char damaged_shipshape2[] = {
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x42, 0x4e, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x48, 0x4c, 0x56, 0x57, 0x60,
	0x00, 0x00, 0x5e, 0x49, 0x4b, 0x57, 0x5f,
	0x00, 0x7d, 0x7e, 0x7c, 0x7e, 0x50, 0x7f,
	0x00, 0x46, 0xd4, 0x49, 0x4c, 0x5d, 0x47,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

void bitswap(unsigned char *b, int lim) {
	unsigned char j, k;
	// fprintf(stderr, "bitswap(%x, %d)\n", b, lim);
	do {
		k = b[lim];
		j = 0;
		j |= (k & 0x01 ? 0x80 : 0);
		j |= (k & 0x02 ? 0x40 : 0);
		j |= (k & 0x04 ? 0x20 : 0);
		j |= (k & 0x08 ? 0x10 : 0);
		j |= (k & 0x10 ? 0x08 : 0);
		j |= (k & 0x20 ? 0x04 : 0);
		j |= (k & 0x40 ? 0x02 : 0);
		j |= (k & 0x80 ? 0x01 : 0);
		b[lim] = j;
	} while(--lim > 0);
}

void clear0bits(unsigned char *b, int lim) {
	do {
		*b++ &= 0xfe;
	} while(--lim > 0);
}

/*
	taipan font file order:
	0-31: `a-z{|}" block
	32-63: @A-Z[\]^_
	64-95: space !"#$%&'()*+,-./0-9:;>=<?

	atari screen code order:
	0-31: space !"#$%&'()*+,-./0-9:;>=<?
	32-63: @A-Z[\]^_
	64-95 graphics chars
	96-127: `a-z and 4 graphics chars
*/

int main(int argc, char **argv) {
	int i, j;
	unsigned char font[1024], xex[6];

	/* The first 1024 bytes of stdin are the Atari ROM font,
		taken from an image of the ROM OS. */
	read(0, font, 1024);

	/* The remaining 768 bytes are the Taipan Apple II font,
		extracted from the .dsk image. Its characters are in a
		different order than the Atari expects them, so use 3 reads
		with appropriate offsets/lengths. The Apple also packs the
		pixels into each byte backwards from what the Atari expects,
		so bitswap() fixes that. */
	read(0, font + (96 * 8), 32 * 8);
	bitswap(font + (96 * 8), 32 * 8);

	read(0, font + (32 * 8), 32 * 8);
	bitswap(font + (32 * 8), 32 * 8);

	read(0, font + (0 * 8), 32 * 8);
	bitswap(font + (0 * 8), 32 * 8);

	/* This stuff is from visual inspection via bitmapdump.pl.
		The Apple uses 7-bit-wide fonts. The high bit isn't displayed,
		and the Apple font has it set on some of the characters. Not
		sure if it has a meaning on the Apple, but it shows up as a
		vertical bar at the right edge of the character here. Since we already
		bit-swapped the font data, clear the 0 bit on the characters
		where it's needed.
	 */
	clear0bits(font + 0x018, 8);
	clear0bits(font + 0x030, 8);
	clear0bits(font + 0x1f8, 7);
	clear0bits(font + 0x301, 7);
	clear0bits(font + 0x308, 8);
	clear0bits(font + 0x330, 8);
	clear0bits(font + 0x3a0, 8);
	clear0bits(font + 0x3d8, 8);
	clear0bits(font + 0x3e8, 8);
	clear0bits(font + 0x040, 16);
	clear0bits(font + 0x1e8, 8);

	/* Fix the vertical bar (put it back to Atari ROM spec), since
		we're using it as a box-drawing character. */
	font[0x3e0] =
	font[0x3e1] =
	font[0x3e2] =
	font[0x3e3] =
	font[0x3e4] =
	font[0x3e5] =
	font[0x3e6] =
	font[0x3e7] = 0x18;

	/* stick ship data where it goes */
	for(i=0; shipdata[i][0]; i++) {
		for(j=0; j<8; j++) {
			font[ shipdata[i][0] * 8 + j ] = shipdata[i][j+1];
		}
	}

	/* if we got an argument, assume it's -x, and write the .xex
		header before the font data. */
	if(argc > 1) {
		xex[0] = xex[1] = 0xff;
		xex[2] = FONT_ADDR % 256; xex[3] = FONT_ADDR / 256; /* load address $2000 */
		xex[4] = 0xff; xex[5] = 0x23; /* end address $23ff */
		write(1, xex, 6);
	}

	/* write the 1K font to stdout. */
	write(1, font, 1024);

	/* create LORCHA.DAT and DAMAGED.DAT, which get incbin'ed by
		draw_lorcha.s. NO error checking here! */
	i = open("LORCHA.DAT", O_WRONLY | O_CREAT, 0666);
	write(i, shipshape, sizeof(shipshape));
	close(i);

	i = open("DAMAGED.DAT", O_WRONLY | O_CREAT, 0666);
	write(i, damaged_shipshape, sizeof(damaged_shipshape));
	close(i);

	i = open("DAMAGED2.DAT", O_WRONLY | O_CREAT, 0666);
	write(i, damaged_shipshape2, sizeof(damaged_shipshape2));
	close(i);

	return 0;
}
