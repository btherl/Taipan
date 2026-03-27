#include <stdint.h>
#include "bignum.h"

char would_overflow(unsigned long value, unsigned long amount) {
	return ((UINT32_MAX - amount) <= value);
}

char bank_withdraw(long amount) {
	bignum(bigamt);

	if(amount < 0) {
		/* can't withdraw all, if too much in bank */
		if(big_cmp(&bank, B_MAXLONG) == 1)
			return 0;
		
		big_copy(&bigamt, &bank);
		big_to_ulong(&bigamt, &amount);
	}

	if(would_overflow(cash, amount)) return 0;

	cash += amount;
	ulong_to_big(&amount, &bigamt);
	big_sub(&bank, &bank, &bigamt);

	return 1;
}

void bank_deposit(long amount) {
	bignum bigamt;

	if(amount < 0) amount = cash;

	cash -= amount;
	ulong_to_big(&amount, &bigamt);
	big_add(&bank, &bank, &bigamt);
}

void bank_interest(void) {
	big_mul(&bank, &bank, &interest_rate);
}
