/* big number functions needed by taipan.c.

	The implementation will actually use the Atari ROM floating point
	routines. To port Taipan to a new cc65 platform, the functions listed
	here will have to be rewritten, but taipan.c itself shouldn't need
	changing (at least, not in relation to bignums!)

	Why call them "bignums" instead of "Float" or something? because
	the whole implementation might get ripped out & replaced with
	64-bit integers, or some other data type. The API shouldn't change
	in that case.

	to declare a bignum:
	bignum(foo);

	...foo actually ends up a pointer (a bignump), which can
	be passed around to the various big_* functions.

   to use the constants:
	bignum(foo) = BIG_0;
	which looks a little weird I admit.

	Notice that our bignum type is signed, even though we
	only have functions to convert to/from unsigned long.
	Only final_stats() and cprintfancy_big() ever deal with
	negative bignums. Actually, big_div() and big_mul() are
	unsigned, as they will never be called with negative
	args. The only signed behaviour we care about here:
	- big_sub() needs to be able to give a negative result.
	- big_cmp() needs to be a signed compare.
*/

/* list all our implementations here */
#define BIGFLOAT 1
#define BIGINT48 2

#ifndef BIGNUM
#error bignum.h requires BIGNUM to be defined
#endif

#if BIGNUM == BIGFLOAT
#include "bigfloat.h"
#elif BIGNUM == BIGINT48
#include "bigint48.h"
#else
#error BIGNUM must be defined to one of: BIGFLOAT BIGINT48
#endif

/****** functions ******/

/* copy dest to src. could be a wrapper for memcpy() */
extern void __fastcall__ big_copy(bignump dest, bignump src);

/* these 2 would be easy to implement, but aren't really needed */
// void int_to_big(int i, bignum *b);
// void uint_to_big(unsigned int i, bignum *b);

/* convert an unsigned long to a bignum */
extern void __fastcall__ ulong_to_big(const unsigned long l, bignump b);

/* convert a bignum to an unsigned long
	returns 0 for success, nonzero for fail (overflow or negative) */
extern char __fastcall__ big_to_ulong(bignump b, unsigned long *l);

/* compare two bignums. like Perl's spaceship operator, <=>
	returns  | if
	---------+----------------
	    0    | a == b
	 positive| a > b
	 negative| a < b

BEWARE: unlike perl's <=>, the return value is *not* guaranteed to
	be 0, 1, or -1. This is more like C's strcmp() or memcmp().
	Do not depend on any particular positive or negative return
	value from this:
	if(big_cmp(a, b) == -1) // WRONG!
	if(big_cmp(a, b) < 0)   // Right.  */
extern signed char __fastcall__ big_cmp(bignump a, bignump b);

/* basic math functions. conceptually they return a boolean for
	success, but currently there is no error checking.
	all can be read as: dest = arg2 OP arg3;
	modulus isn't implemented as taipan doesn't use it for the bank.
	These are __cdecl__ *not* __fastcall__ !!
 */
extern char __cdecl__ big_add(bignump dest, bignump addend1, bignump addend2);
extern char __cdecl__ big_sub(bignump dest, bignump minuend, bignump subtrahend);
extern char __cdecl__ big_mul(bignump dest, bignump multiplicand, bignump multiplier);
extern char __cdecl__ big_div(bignump dest, bignump dividend, bignump divisor);

/* negation: b = -b, or b *= -1 */
#if BIGNUM != BIGFLOAT
extern void __fastcall__ big_negate(bignump b);
#endif

/* returns true if the bank is maxed out. We do this by checking the exponent
	byte, so the "max" is tied to the bignum implementation, which is why its
	prototype is here rather than bank.h. For Atari floats, it's 1.0e+14, or
	100 trillion. For bigint48 it would be something like, bit 46 is nonzero,
	140.7 trillion.

	With floats, if you deposit 1 in the bank at the start of the game and never deposit
	more, the interest would max it out in 1915 (661 turns of play).

	ended up not implementing this, I don't think anyone will ever have the patience
	to play long enough to overflow an A8 float (9.0e+97) or a 48-bit int (2**48-1,
	or 281.5 trillion).
extern char __fastcall__ bank_maxed_out(bignump b);
 */

/* print a bignum, Taipan-style. Code for this lives in taipan.c actually. */
extern void cprintfancy_big(bignump b);
