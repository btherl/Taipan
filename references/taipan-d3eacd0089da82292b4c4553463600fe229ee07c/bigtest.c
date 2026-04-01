#include <stdio.h>
#include <peekpoke.h>

#include "bignum.h"

unsigned long values[] = {
	123456789L,
	12345678L,
	1234567L,
	123456L,
	65536L,
	65535L,
	4294966190L, /* works, (2**32-1)-1105 */
	4294967295L,
	665,
	78,
	1,
	0
};

int main(void) {
	char i, j;
	unsigned long got;
	bignum(a);
	bignum(b);
	bignum(c);
	bignum(zero) = BIG_0;

	ulong_to_big(1234L, a);
	ulong_to_big(10L, b);
	// got = cformat_big(&i, a);
	// printf("got %lu, mag %d\n", got, i);
	for(i = 0; i < 11; i++) {
		cprintfancy_big(a);
		big_copy(c, zero);
		big_copy(c, a);
		cprintfancy_big(c);
		big_mul(a, a, b);
	}

	/*
	ulong_to_big(5L, a);
	for(i = 0; i < 10; i++) {
		ulong_to_big((unsigned long)i, b);
		j = big_cmp(a, b);
		printf("5 cmp %d: %d\n", i, j);
	}
	*/

	/*
	unsigned long al = 111, bl = 2, result;

	ulong_to_big(al, a);
	ulong_to_big(bl, b);
	big_div(a, a, b);
	big_to_ulong(a, &result);
	printf("%lu\n", result);
	*/
hang: goto hang;
}

int oldmain(void) {
	char i, j;
	unsigned long l = 123456789L; // 075bcd15, or 52501 + 256 * 1883
	bignum(b);

	/*
	ulong_to_big(l, b);
	for(i=0; i<6; i++)
		printf("%02x ", b[i]);
		*/

	POKEW(19,0);
	for(i=0; i < (sizeof(values)) / (sizeof(long)); i++) {
		l = values[i];
		printf("%lu: ", l);
		ulong_to_big(l, b);
		l = 666L;
		j = big_to_ulong(b, &l);
		printf("%d %lu\n", j, l);
	}

	printf("%d\n", PEEK(20)+256*PEEK(19));
// hang: goto hang;
}
