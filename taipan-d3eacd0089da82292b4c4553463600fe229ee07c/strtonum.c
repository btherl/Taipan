#include <limits.h>

/* Convert a string to a long unsigned int, tiny version.
	Based on strtoul.c from cc65 libsrc, but stripped down:
	- only supports base 10.
	- no leading +, -, 0, 0x support.
	- does not skip leading spaces.
	- returns ULONG_MAX on overflow, but does not set errno.
	- overflows at 4294967290 rather than 4294967296.
	- no endptr argument, so no way to tell how many character
	  were converted.

	taipan's input routines stop the player from typing invalid
	characters, so nobody will miss the error checking. using
	this instead of strtoul saves 743 bytes.
 */

/* ULONG_MAX / 10 */
#define MAX_VAL 429496729

unsigned long __fastcall__ strtonum(const char* nptr) {
	unsigned long ret = 0;
	unsigned char digit;

	/* Convert the number */
	while(*nptr >= '0' && *nptr <= '9') {
		/* Convert the digit into a numeric value */
		digit = *nptr - '0';

		/* Don't accept anything that makes the final value invalid */
		if(ret > MAX_VAL)
			return ULONG_MAX;

		/* Calculate the next value if digit is not invalid */
		ret = (ret * 10) + digit;

		/* Next character from input */
		++nptr;
	}

	/* Return the result */
	return ret;
}

#ifdef STRTONUM_TEST
#include <stdio.h>
int main(void) {
	printf("%lu\n", strtonum("123"));
	printf("%lu\n", strtonum("98765"));
	printf("%lu\n", strtonum("429496730"));
	printf("%lu\n", strtonum("4294967295"));
	printf("%lu\n", strtonum("5555555555"));
	printf("%lu\n", strtonum(" "));
hang: goto hang;
	return 0;
}
#endif
