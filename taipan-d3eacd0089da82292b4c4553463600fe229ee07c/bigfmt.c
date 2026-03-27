#include <conio.h>
#include "bignum.h"

bignum(big1M) = BIG_1M;
bignum(big100M) = BIG_100M;
bignum(big1B) = BIG_1B;

/*
Requires a bit of explanation. b's value will always be zero or
positive, and can range up to 1.0e+14 (aka 100 trillion).

magnitude values:
0 - result is used as-is (result range 0 - 999999)
    b range 0 - 999999
1 - result is in 100000's, print result/10 Million (range 0-9999)
    b range 1,000,000 - 999,999,999 (999 Million)
2 - result is in 100 millions, print result/10 Billion (range 0-9999)
    b range 1,000,000,000 (1 Billion) - 999,999,999,999 (1 trillion - 1)

The calling code decides whether or not to print a decimal point
and 10ths digit (using integer math only).
*/

unsigned long cformat_big(char *magnitude, bignump b) {
	bignum(tmp);
	unsigned long ret;
	if(big_cmp(b, big1M) < 0) {
		*magnitude = 0;
		big_to_ulong(b, &ret);
	} else if(big_cmp(b, big1B) < 0) {
		*magnitude = 1;
		big_to_ulong(b, &ret);
		ret /= 100000L;
	} else {
		*magnitude = 2;
		big_div(tmp, b, big100M);
		big_to_ulong(tmp, &ret);
	}
	return ret;
}

void cprintfancy_big(bignump b) {
	char m;
	unsigned long l = cformat_big(&m, b);
	if(!m) {
		cprintf("%lu", l);
	} else {
		if(l > 100) {
			cprintf("%lu ", l / 10L);
		} else {
			cprintf("%lu.%lu ", l / 10L, l % 10L);
		}
		cputc(m == 1 ? 'M' : 'B');
		cputs("illion");
	}
	cputs("\r\n");
}
