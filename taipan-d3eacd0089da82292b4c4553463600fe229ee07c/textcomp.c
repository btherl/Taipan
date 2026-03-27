/* textcomp.c - compress strings of text to 6 bits per byte.
	loosely based on the z-machine's ZSCII compression.

	Example: "Taipan" (7 bytes, including null terminator) encodes as
	0xb8 0x12 0x50 0x04 0xe0 0x00 (6 bytes).

	Longer strings approach 75% compression ratio. Sadly, the result
	has to be padded to an 8-bit byte boundary, or else we'd get 75%
	for every string.

	Input length | Encoded length | Ratio
	(incl. null) | (bytes)        |
	2            | 2              | 100%, don't bother
	3            | 3              | 100%, don't bother
	4            | 3              | 75%
	5            | 4              | 80%
	6            | 5              | 83%
	7            | 6              | 86%
	8            | 6              | 75%
	9            | 7              | 78%
	10           | 8              | 80%
	11           | 9              | 82%
	12           | 9              | 75%
	13           | 10             | 77%
	14           | 11             | 79%
	15           | 12             | 80%
	16           | 12             | 75%
	...etc etc

	No encoded string can be over 256 bytes long, as the decompressor
	can't currently handle it.

	The alphabet contains only upper/lowercase letters, space, newline,
	and some punctuation. In particular, numbers are not supported.

	alphabet:
	0 = end
	1-26 = a-z
	27-52 = A-Z
	53 = space
	54 = !
	55 = %
	56 = ,
	57 = .
	58 = ?
	59 = :
	60 = '
	61 = (
	62 = )
	63 = newline

	All the strings used by taipan.c are listed in messages.msg, except
	the help messages in the cartridge build (which are in helpmsgs.msg).
	The perl script messages.pl calls this program (textcomp) once
	per string, and outputs C source consisting of the encoded versions.
	Each string in the __END__ section is preceded by a name, and the
	generated C source uses these names with M_ prefixed.

	taipan.c calls the function print_msg(const char *) to decode and
	print an encoded message. The decoding step slows down printing a bit,
	but it's not really noticeable. cputc() is used for printing, so it
	respects the reverse video setting (set by rvs_on() and rvs_off()).
	The task of replacing cputs("some string") with print_msg(M_some_string)
	was done manually.

	When a newline is printed, our modified conio moves the cursor to the
	start of the next line, so no \r's are needed. Any \r sequences listed
	in the .msg files are discarded before encoding is done.

	Since no prompts ever use capital Z, it's used as an escape character
	for dictionary lookups (e.g. Za = "Li Yuen", Zb = "Elder Brother").
	This program doesn't do that, it's done by messages.pl, and textdecomp.s
	does the dictionary extraction.
*/

#include <stdio.h>
#include <stdlib.h>

unsigned char out[1024];
int bitcount = 0;

int getcode(int c) {
	if(c >= 'a' && c <= 'z')
		return c - 'a' + 1;
	if(c >= 'A' && c <= 'Z')
		return c - 'A' + 27;

	switch(c) {
		case ' ': return 53;
		case '!': return 54;
		case '%': return 55;
		case ',': return 56;
		case '.': return 57;
		case '?': return 58;
		case ':': return 59;
		case '\'': return 60;
		case '(': return 61;
		case ')': return 62;
		case '\n': return 63;
		case '\r': break;
		default:
			fprintf(stderr, "unhandled ASCII code %d\n", c);
			exit(1);
	}

	return 0; /* never executes, shut gcc -Wall up */
}

void appendbit(unsigned char b) {
	int pos = bitcount / 8;
	int bitpos = 7 - (bitcount % 8);
	unsigned char val = b << bitpos;
	out[pos] |= val;
	fprintf(stderr, "%d: appending bit %d at pos %d, bitpos %d, value $%02x\n", bitcount, b, pos, bitpos, val);
	bitcount++;
}

void appendcode(int code) {
	int bit;
	for(bit = 0x20; bit > 0; bit >>= 1) {
		appendbit((code & bit) != 0);
	}
}

int main(int argc, char **argv) {
	int c, code, count = 1; /* 1 to account for null terminator */

	while((c = getchar()) != EOF) {
		code = getcode(c);
		fprintf(stderr, "c == %d, code == %d\n", c, code);
		appendcode(code);
		count++;
	}
	appendcode(0);

	code = 0;
	for(c = 0; c < ((bitcount + 7) / 8); c++) {
		printf("0x%02x ", out[c]);
		code++;
	}

	if(code > 256) {
		fprintf(stderr, "input too long\n");
		exit(1);
	}

	fprintf(stderr, "%d bytes in (added null), %d bytes out, ratio %.2f\n",
			count, code, (float)(code)/(float)count);
	return 0;
}
