/* Taipan! for Atari 8-bit. Ported from the Linux/curses version,
   which was based on the original Applesoft BASIC version. */

/* we're actually using a locally modified conio, see conio/README */
#include "conio-local.h"

#include <stdlib.h>    /* rand() srand() exit() */
#include <stdint.h>    /* UINT32_MAX */
#include <peekpoke.h>  /* PEEK() PEEKW() POKE() POKEW() */

#include "sounds.h"

#ifdef BIGNUM
#include "bignum.h"
#endif

/**** These defines should be disabled for normal gameplay.
      Don't leave any of them enabled for a release or a
      normal test build. */

/* define this to debug the random number seeding process in
	init_game() */
// #define RANDSEED_TEST

/* define this for testing sea_battle(). it causes a pirate
	attack every time you leave port. */
// #define COMBAT_TEST

/* define this to show internals of damage calculation */
// #define DAMAGE_TEST

/* define this to start the game in the year 1869, with
	1000 capacity, 20 guns, and 1 billion cash and bank. */
// #define TIMEWARP

/* define this to start the game in a 99% damaged ship */
// #define ALMOST_DEAD

/* define this to test the mchenry() routine by entering
	damage and capacity numbers directly */
// #define MCHENRY_TEST

/* define this to test the cprintfancy_big() routine */
// #define BIGNUM_TEST

/* define this to show frames/scanlines timing for port_stats() */
// #define PORT_STAT_TIMER

/* define this to test lorcha drawing/damage */
// #define LORCHA_TEST

/* define this to test final_stats() */
// #define FINAL_STATS_TEST

/**** atari-specific stuff */

/* values returned by cgetc() for backspace/enter/delete keys */
#define BKSP 0x7e
#define ENTER 0x9b
#define DEL 0x9c

/* wait up to 5 sec for a keypress. returns 0 if no key pressed */
extern char __fastcall__ timed_getch(void);

/* custom Atari-aware cgetc() wrapper. returns only non-inverse
	plain ASCII characters, except EOL and BS. Unlike the real cgetc(),
	it's an unsigned char, and can't return -1 for failure (but, it will never
	fail. real cgetc() never fails either, even if user hits Break) */
extern unsigned char agetc(void);

/* wrapper for agetc(): lowercases letters */
extern unsigned char lcgetc(void);

/* wrapper for agetc(): returns only numbers, a, enter, backspace */
extern unsigned char numgetc(void);

/* wrapper for agetc(): returns only y or n.
	dflt is 'y' or 'n' to set the default answer if the user presses Enter,
	or 0 for no default (waits until user presses either y or n) */
extern unsigned char __fastcall__ yngetc(char dflt);

/* sleep for j jiffies (no PAL adjustment at the moment) */
extern void __fastcall__ jsleep(unsigned int j);

/* sleep for j jiffies unless turbo is true */
extern void __fastcall__ tjsleep(unsigned int j);

/* flash screen when we're hit in combat */
extern void explosion(void);

extern void __fastcall__ cblank(unsigned char count);
extern void __fastcall__ backspace(void);

extern void __fastcall__ addrandbits(char);
extern void __fastcall__ initrand(void);
#define randi() ((unsigned int)rand())

extern unsigned char rand1to3(void);

/* random long, 0 to 2**32-1 */
extern unsigned long __fastcall__ randl(void);

/* defined in portstat.s, this is the contents of PORTSTAT.DAT.
	used to quickly redraw the port stats screen.
	If ever PORTSTAT.DAT needs to be regenerated, use mkportstats.c  */
extern const char *port_stat_screen;

/* boolean, whether or not port_stats() needs to redraw the
	static parts of the port stats screen (by copying
	port_stat_screen into screen RAM) */
char port_stat_dirty = 1,
	  bank_dirty = 1,
	  cash_dirty = 1;

/* boolean, turbo fighting mode. cleared on entry to sea_battle(), set
	when user enters turbo mode. has no effect outside of sea_battle() so
	the caller doesn't have to reset it. */
unsigned char turbo;

/* asm curses/conio funcs from console.s. Old C versions moved to
	oldcurses.c for reference. */
extern void clrtobot(void);
extern void clrtoeol(void);
/* print 'count' spaces: */
extern void __fastcall__ cspaces(unsigned char count);

/* same as gotoxy(0, y). replacing all the gotoxy(0, foo) with
	this saves 208 bytes! */
extern void __fastcall__ gotox0y(char y);

/* replacing all gotox0y(3) and gotox0y(22) calls with these
	save us 43 bytes. */
extern void __fastcall__ gotox0y3(void); /* same as gotoxy(0,3) */
extern void __fastcall__ gotox0y22(void); /* same as gotoxy(0,22) */
extern void __fastcall__ gotox0y3_clrtoeol(void); /* same as gotoxy(0,3); clrtoeol(); */

/* same as gotoxy(0,3); clrtoeol(); print_msg(x); */
extern void __fastcall__ print_combat_msg(const char *);

/* each prints one specific character */
extern void crlf(void);
extern void cspace(void);
extern void cputc_s(void);
extern void cprint_bang(void);
extern void cprint_pipe(void);
extern void cprint_period(void);
extern void cputc0(void);

/* each print 2 characters */
extern void comma_space(void);
extern void cprint_question_space(void);
extern void cprint_colon_space(void);
extern void cprint_taipan_prompt(void);

/* our own clr_screen(), don't use conio's clrscr() */
extern void clr_screen(void);

extern void __fastcall__ cblankto(unsigned char dest);

/* avoid calling/linking conio's revers() function. This saves us
	49 bytes (2 per call to revers(), plus these functions are smaller
	than conio's revers() because they return void) */
extern void rvs_on(void);
extern void rvs_off(void);

/* asm funcs from draw_lorcha.s for drawing/animating enemy ships.
	used by sea_battle() */
extern void __fastcall__ draw_lorcha(int which);
extern void __fastcall__ flash_lorcha(int which);
extern void __fastcall__ damage_lorcha(int which);
extern void __fastcall__ sink_lorcha(int which);
extern void __fastcall__ clear_lorcha(int which);

/* redraw the static part of the port status screen, but only
	if nothing has set port_stat_dirty */
extern void redraw_port_stat(void);

/* this pragma places compiled C code in bank 3 of the cartridge,
   so it doesn't need to be copied to RAM (speeds startup).
   currently commented out, since we want to make room in bank2
   for the help text (when that gets added).
 */
/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/

/* this didn't work out, bummer. */
// extern void __fastcall__ waitvcount(unsigned char c);

/**** End of atari-specific stuff. Supposed to be, anyway. */

/* messages.c is generated by messages.pl */
#include "messages.c"

#ifdef GAME_HELP
#  include "helpmsgs.h"
#  include "helpmsgs.c"
#else
#  define SET_HELP(x)
#  define CLEAR_HELP
#endif

extern void __fastcall__ print_msg(const char *msg);

/* old version of this used to just 'return randl()%arg'.
	If arg were 0, the return value would be the unmodified
	result from randl() (x % 0 == x, in cc65). If it were 1,
	the return value would always be 1 (no randomness there). */
unsigned long randlmod(unsigned long arg) {
	unsigned long r = randl();
	if(!arg)     return 0;
	if(arg == 1) return r & 0x01;
	return r % arg;
}

unsigned char one_chance_in(unsigned char odds) {
	return ( (randi() % odds) == 0);
}

/* print 's' if num==1, otherwise do nothing. */
extern void __fastcall__ pluralize(int num);

/* print 1 space */
/*
void cspace(void) {
	cputc(' ');
}
*/

/* print the letter s (for pluralization) */
/*
void cputc_s(void) {
	cputc('s');
}
*/

/* print 'count' spaces, but leave the cursor where it was.
	been rewritten in asm, see console.s */
/*
void cblank(unsigned char count) {
	char oldx = wherex();
	char oldy = wherey();
	cspaces(count);
	gotoxy(oldx, oldy);
}
*/

/* conio doesn't back up the cursor if you cputc(BKSP), it
	prints the graphics character instead. Could use putchar(),
	but using stdio links a bunch of extra support code.
	Been rewritten in asm, see console.s */
/*
void backspace() {
	gotox(wherex()-1);
	cblank(1);
}
*/


extern unsigned char get_item_port(void);
extern unsigned char get_item_battle(void);

/*
	rewritten in asm, in timed_getch.s, here's the original:
unsigned char get_item(unsigned char allow_all) {
	for(;;) {
		switch(lcgetc()) {
			case 'o': return 0;
			case 's': return 1;
			case 'a': return 2;
			case 'g': return 3;
			case '*': if(allow_all) return 4; // else fall thru
			default: break;
		}
	}
}
*/

/* sound-and-getch functions cost 6 bytes each, but save 3 bytes
	every time they replace 2 function calls. Total saving works
	out to 56 bytes, so worth doing.
 */
void good_joss_timed_getch() {
	good_joss_sound();
	timed_getch();
}

void bad_joss_timed_getch() {
	bad_joss_sound();
	timed_getch();
}

void under_attack_timed_getch() {
	under_attack_sound();
	timed_getch();
}

/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/

/* modified ultoa() with hardcoded radix */
extern char *ultostr(unsigned long value, char* s);

/* if your debt goes above this, Elder Brother Wu has
	you assassinated, game over. Value is:
	int((2**31 - 1) / 1.1) */
#define DEBT_MAX 1952257860L
char wu_assassin;

/* maximum length of the user's firm name. was 22, no reason not to allow 24. */
#define MAX_FIRM 24

/* taipan functions (modified as little as possible) */
#define GENERIC 1
#define LI_YUEN 2

/* title screen now a separate xex segment (see Makefile for details) */
// void splash_intro(void);

unsigned long get_num(void);
void set_prices(void);
void port_stats(void);
int port_choices(void); /* making this an char actually wastes 1 byte! */
void new_ship(void);
void new_gun(void);
void li_yuen_extortion(void);
void elder_brother_wu(void);
void good_prices(void);
void buy(void);
void sell(void);
void visit_bank(void);
void transfer(void);
void quit(void);
void overload(void);
char sea_battle(char id, int num_ships);
void fight_stats(int ships);
void mchenry(void);
void retire(void);
void final_stats(void);
void you_only_have(unsigned char in_bank);

/* these 3 are from cprintul.s */
extern void cprintulong(unsigned long ul);
extern void cprintuint(unsigned int ui);
extern void cprintuchar(unsigned char uc);

void cprintfancy(unsigned long num);
void cprintfancy_centered(unsigned long num);
void too_much_cash(void);
char would_overflow(unsigned long a, unsigned long b);
int get_time(void);
void cprint_taipan_comma(void);
void cprint_taipan_colon(void);
void cprint_taipan_bang(void);
void cprint_taipan_period(void);
void cprint_taipan_prompt(void);
void cprint_elder_brother_wu(void);
// void cprint_li_yuen(void);
void cprint_firm_colon(void);
char get_ship_status(void);

/* local replacement for strtoul, see strtonum.c */
unsigned long __fastcall__ strtonum(const char* nptr);

unsigned char firmpos;

int ships_on_screen[10];

/* arrayutils.s */
extern char no_ships_on_screen(void);
extern void clear_ships_on_screen(void);
extern char have_no_cargo(void);
extern char hold_is_empty(void);
extern char hkw_is_empty(void);
extern void clear_hold(void);
extern void clear_hkw(void);

/* use page 6 for these buffers, for .xex build. Otherwise they're BSS. */
#ifdef CART_TARGET
char firm[MAX_FIRM + 1];
char num_buf[20];
#else
char *firm = (char *) 0x680;
char *num_buf = (char *) 0x600;
#endif

// char    *item[] = { "Opium", "Silk", "Arms", "General Cargo" };
const char * const item[] = { M_opium, M_silk, M_arms, M_gen_cargo };

extern void __fastcall__ print_item(char item); // textdecomp.s

/*
const char *location[] = { "At sea", "Hong Kong", "Shanghai", "Nagasaki",
                        "Saigon", "Manila", "Singapore", "Batavia" };
								*/

const char * const location[] = { M_at_sea, M_hong_kong, M_shanghai,
                           M_nagasaki, M_saigon, M_manila,
                           M_singapore, M_batavia };

extern void __fastcall__ print_location(char loc); // textdecomp.s

extern void __fastcall__ print_month(void); // console.s

const char * const st[] = {
	"\xc3\xf2\xe9\xf4\xe9\xe3\xe1\xec", // inverse "Critical"
	"\xa0\xa0\xd0\xef\xef\xf2",         // inverse "  Poor"
	"  Fair",
	"  Good",
	" Prime",
	"Perfect"
};

extern void __fastcall__ print_status_desc(char s); // console.s

#ifdef BIGNUM
bignum(bank) = BIG_0;
bignum(interest_denom) = BIG_200;
bignum(big_max_ulong) = BIG_MAX_ULONG;
#else
unsigned long bank = 0;
#endif

unsigned long cash,
        debt,
        booty;
        // ec           = 20,
        // ed           = 1; // used to be a float, 0.5

unsigned long    price[4];

const int base_price[4][8] = {
	/* each row: first number is base price, the rest are
		multiplier at each port (1-7) */
	{1000, 11, 16, 15, 14, 12, 10, 13},    /* opium */
	{100,  11, 14, 15, 16, 10, 13, 12},    /* silk */
	{10,   12, 16, 10, 11, 13, 14, 15},    /* arms */
	{1,    10, 11, 12, 13, 14, 15, 16} };  /* general */

/* hkw_ is the warehouse, hold_ is how much of each item is
	in your hold. both need to be unsigned (makes no sense to
	have negative amounts in warehouse or hold). hold_ needs
	to be a long because it's entirely possible to buy e.g. over
	32768 of some item later in the game. You won't be able to
	leave port, so you'll have to get rid of it on the same turn,
	but we still have to stop it overflowing a 16-bit int.

	hkw_ doesn't need to be long, since you can never have more
	than 10,000 of any one item. */
unsigned int hkw_[4];
unsigned long hold_[4];

/* this really can go negative (meaning, your ship is
   overloaded). It needs to be a long though. At some
   point, it *still* might overflow, e.g. if general cargo
   drops to 1, you have over 2**31-1 in cash, and you
   buy that many general cargo...  Probably should limit the
   amount of cargo the player can buy per transaction, but
   even then, they can do multiple transactions on the same
   turn. Need a signed version of would_overflow() to do
   this right. */
long hold;

/* these being negative would be a Bad Thing */
unsigned char month;
unsigned int guns,
             year,
		       ec,
		       ed;

/* ec+=20, ed++ every game-year (12 turns).
	player would have to play until 15 Jan 5168 to overflow ec. */

unsigned char port,
        bp,
		  li,
		  wu_warn,
		  wu_bailout;

// these need to be longs to avoid int overflow when
// displaying ship status.
long damage, capacity, newdamage;

/* a bunch of text strings that occur multiple times in the
	prompts. Each of these actually does save a few bytes, but
	there are diminishing returns. Anything that only occurs twice
	might or might not be worth turning into a function. */

/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/

void how_much(void) {
	// cputs("How much ");
	// print_msg(M_how_much_spc);
	print_msg(M_how_much);
	cspace();
}

void how_much_will_you(void) {
	how_much();
	// cputs("will you ");
	print_msg(M_will_you);
}

void cprint_bad_joss() {
	// cputs("Bad Joss!!\n");
	print_msg(M_bad_joss);
}

/*
void crlf(void) {
	// cputs("\n");
	print_msg(M_crlf);
}
*/

void cprint_taipan(void) {
	// cputs("Taipan");
	print_msg(M_taipan);
}

/*
void comma_space(void) {
	cputs(", ");
}
*/

void cprint_taipan_comma(void) {
	cprint_taipan();
	comma_space();
}

/*
void cprint_colon_space(void) {
	cputs(": ");
}
*/

void cprint_taipan_colon(void) {
	cprint_taipan();
	cprint_colon_space();
}

/*
void cprint_bang(void) {
	cputc('!');
}

void cprint_pipe(void) {
	cputc('|');
}
*/

void cprint_taipan_bang(void) {
	comma_space();
	cprint_taipan();
	cprint_bang();
}

void cprint_taipan_period(void) {
	comma_space();
	cprint_taipan();
	// cputc('.');
	cprint_period();
}

	/*
void cprint_question_space(void) {
	cputs("? ");
}
*/

/*
void cprint_taipan_prompt(void) {
	comma_space();
	cprint_taipan();
	cprint_question_space();
}
*/

void do_you_wish(void) {
	// cputs("do you wish ");
	print_msg(M_do_you_wish);
}

void cprint_elder_brother_wu(void) {
	// cputs("Elder Brother Wu ");
	print_msg(M_elder_brother_wu);
}

/* This one only saves space when Li Yuen occurs at the start
	of a string, not in the middle */
/*
void cprint_li_yuen(void) {
	// cputs("Li Yuen");
	print_msg(M_li_yuen);
}
*/

void cprint_Do_you_want(void) {
	// cputs("Do you want ");
	print_msg(M_do_you_want);
}

void cprint_firm_colon(void) {
	// cputs("Firm:");
	print_msg(M_firm_colon);
}

/* making this a function saved 52 bytes */
char get_ship_status(void) {
	return 100 - ((damage * 100L) / capacity);
}

/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/
void print_bar_line(void) {
	cprint_pipe();
	cspaces(38);
	cprint_pipe();
}
/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/


#ifdef BIGNUM
bignum(big1T) = BIG_1T;
bignum(big1B) = BIG_1B;
bignum(big1M) = BIG_1M;
bignum(big1K) = BIG_1K;
bignum(big0) = BIG_0;
#endif

#ifdef RANDSEED_TEST
extern char randseed[4]; /* aka unsigned long randseed */
void debug_randseed(void) {
	char oldx = PEEK(85); /* COLCRS */
	char oldy = PEEK(84); /* ROWCRS */
	char i;
	gotox0y22();
	for(i = 0; i < 4; i++) {
		cprintuchar(randseed[i]);
		cspace();
	}
	clrtoeol();
	gotoxy(oldx, oldy);
}

#endif

/* moved cash_or_guns() and name_firm() to inline code here.
	saves 10 bytes. */
void init_game(void) {
	unsigned char input, firmlen = 0;

#ifdef BIGNUM
	big_copy(bank, big0);
#else
	bank         = 0;
#endif
	clear_hkw();
	clear_hold();
	hold         = 0;
	damage       = 0;
	wu_warn      = 0;
	wu_bailout   = 0;
	wu_assassin  = 0;
	month        = 1;
	port         = 1;
	ed           = 1;
	capacity     = 60;
	year         = 1860;
	ec           = 20;

/* This used to be a separate name_firm() function.
   TODO: rewrite in asm, or at least better C */
   clr_screen();

	/* old version, readable, but compiles to 78 byte more
		than the new version below.
	chlinexy(1, 7, 38);
	chlinexy(1, 16, 38);
	cvlinexy(0, 8, 8);
	cvlinexy(39, 8, 8);
	cputcxy(0, 7, 17); // upper left corner
	cputcxy(0, 16, 26); // lower left corner
	cputcxy(39, 7, 5); // upper right corner
	cputcxy(39, 16, 3); // lower right corner
	gotoxy(6, 9);
	cprint_taipan_comma();
	gotoxy(2, 11);
	cputs("What will you name your");
	gotoxy(6, 13);
	cprint_firm_colon();
	chlinexy(12, 14, 22);
	*/

	gotoy(7);
	cputc(17);
	chline(38);
	cputc(5);
	print_bar_line();
	cprint_pipe();
	cspaces(4);
	cprint_taipan_comma();
	cspaces(26);
	cprint_pipe();
	print_bar_line();
	cprint_pipe();
	// cputs(" What will you name your");
	print_msg(M_what_will_you_name_firm);
	cspaces(14);
	cprint_pipe();
	print_bar_line();
	cprint_pipe();
	cspaces(4);
	cprint_firm_colon();
	cspaces(29);
	cprint_pipe();
	cprint_pipe();
	cspaces(10);
	chline(MAX_FIRM);
	cspaces(4);
	cprint_pipe();
	print_bar_line();
	cputc(26);
	chline(38);
	cputc(3);

	gotoxy(11, 13);

	initrand();

	#ifdef RANDSEED_TEST
	debug_randseed();
	#endif

   while(1) {
		input = agetc();
		addrandbits(input);
		#ifdef RANDSEED_TEST
		debug_randseed();
		#endif
		if(input == ENTER) {
			if(firmlen)
				break;
			else
				bad_joss_sound();
		} else if(input == DEL) {
			gotox(12);
			cblank(22);
			firmlen = 0;
		} else if(input == BKSP) {
			if(firmlen) {
				backspace();
				--firmlen;
			}
		} else if(firmlen < MAX_FIRM) {
			cputc(firm[firmlen++] = input | 0x80);
		}
	}

   firm[firmlen] = '\0';
	firmpos = 12 - firmlen / 2;

	/* end of name_firm() */

	/* formerly a separate cash_or_guns() function. */
   clr_screen();
	cprint_Do_you_want();
   // cputs("to start . . .\n\n");
	print_msg(M_to_start);
   // cputs("  1) With cash (and a debt)\n\n");
   cputs("  1");
	print_msg(M_with_cash);
	cspaces(16);
   cputs("-- or --\n\n  2");
   // cputs("  2) With five guns and no cash\n");
	print_msg(M_with_5_guns);
	cspaces(16);
   // cputs("(But no debt!)");
	print_msg(M_but_no_debt);
	gotoxy(10, 10);
	// cputc('?');
	cprint_question_space();

   do {
      input = agetc();
   } while ((input != '1') && (input != '2'));

	capacity = 60;
	damage = 0;
   if(input == '1') {
      cash = 400;
      debt = 5000;
      hold = 60;
      guns = 0;
      li = 0;
      bp = 10;
   } else {
#ifdef TIMEWARP
		year = 1869;
      cash = 1000000000L;
      // cash = 4294000000L;
      // cash = 3500000L;
#  ifdef BIGNUM
		big_copy(bank, big1M);
		big_mul(bank, bank, big1M);
#  else
      bank = 1000000000L;
#  endif
      debt = 0;
		capacity = 1000;
      hold = 800;
      guns = 20;
      li = 1;
      bp = 7;
		ed = 9;
		ec = 90;
#else /* !TIMEWARP */
      cash = 0;
      debt = 0;
      hold = 10;
      guns = 5;
      li = 1;
      bp = 7;
#endif /* TIMEWARP */
#ifdef ALMOST_DEAD
		damage = capacity - 1;
#endif
   }
	/* end of cash_or_guns() */

	for(input = PEEK(20); input > 0; --input)
		randi();
	#ifdef RANDSEED_TEST
	debug_randseed();
	#endif

	set_prices();
}

/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/

#ifdef BIGNUM
/* what we should have:
	For Million/Billion, 3 significant digits.
	range          printed as
	0..999999      stet
	1M..10M-1      1.23 Million
	10M..100M-1    10.2 Million, 100 Million
	100M..1M-1     100 Million, 999 Million
	1B..10B-1      1.23 Billion
	10B..100B-1    10.2 Billion, 100 Billion
	100B..1T-1     100 Billion
	1T..inf        1 Trillion+!
*/
void cprintfancy_big(bignump b) {
	bignum(tmp);
	unsigned long leftdigits = 0L;
	unsigned char rightdigits = 0, letter = 'M', leading0 = 0;

	big_copy(tmp, b);

	/* This is gross, but it saves 13 bytes here, plus another
		14 because we can remove big_negate from bigfloat.s. */
#if BIGNUM == BIGFLOAT
	if(tmp[0] & 0x80) {
		cputc('-');
		tmp[0] ^= 0x80;
	}
#else
	if(big_cmp(tmp, big0) < 0) {
		cputc('-');
		big_negate(tmp);
	}
#endif

	if(big_cmp(tmp, big1T) >= 0) {
		// inverse "1 Trillion+!":
		cputs("\xb1\xa0\xd4\xf2\xe9\xec\xec\xe9\xef\xee\xab\xa1");
		return;
	}

	/* for >= 1B, divide by 1M */
	if(big_cmp(tmp, big1B) >= 0) {
		big_div(tmp, tmp, big1K);
		letter = 'B';
	}

	big_to_ulong(tmp, &leftdigits);

	if(big_cmp(tmp, big1M) < 0) { /* 0..999999 */
		letter = 0;
	} else if(leftdigits < 10000000L) { /* 1M..10M-1 */
		leftdigits /= 10000L;
		rightdigits = (unsigned char)(leftdigits % 100L);
		leftdigits /= 100L;
		if(rightdigits < 10) leading0 = 1;
	} else if(leftdigits < 100000000L) { /* 10M..100M-1 */
		leftdigits /= 100000L;
		rightdigits = (unsigned char)(leftdigits % 10L);
		leftdigits /= 10L;
	} else {
		leftdigits /= 1000000L;
	}

	cprintulong(leftdigits);
	if(rightdigits) {
		// cputc('.');
		cprint_period();
		if(leading0) cputc0();
		// cprintulong((unsigned long)rightdigits);
		cprintuchar(rightdigits);
	}

	if(letter) {
		cspace();
		cputc(letter);
		cputs("illion");
		// print_msg(M_illion);
	}
}
#endif

/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/

int get_time(void) {
	return ((year - 1860) * 12) + month;
}

/* print an int or long as a string, conio-style */
/*
void cprintulong(unsigned long ul) {
	cputs(ultostr(ul, num_buf));
}
*/

void at_sea(void) {
	gotoxy(30, 6);
	clrtoeol();
	cspace();
	rvs_on();
	// cputs(location[0]);
	print_location(0);
	rvs_off();
}

/* these were rewritten in asm to save 5 bytes, they live in console.s */
extern void prepare_report(void);
extern void clear_msg_window(void);

void compradores_report(void) {
	prepare_report();
	// cputs("Comprador's Report\n\n");
	print_msg(M_compradors_report);
}

void captains_report(void) {
	prepare_report();
   // cputs("  Captain's Report\n\n");
	print_msg(M_captains_report);
}

void overload(void) {
	compradores_report();
   // cputs("Your ship is overloaded");
	print_msg(M_overloaded);
	good_joss_timed_getch();
   return;
}

unsigned int gunamt(void) {
	return randi()%(1000 * (get_time() + 5) / 6);
}

/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/

void new_ship(void) {
   unsigned long amount;

	/* TODO: check against applesoft, line 1060 */
	amount = gunamt() * (capacity / 50) + 1000;

   if(cash < amount) {
      return;
   }

	compradores_report();
	// cputs("Do you wish to trade in your ");
	print_msg(M_wish_to_trade);
   if(damage > 0) {
		cputs("\xe4\xe1\xed\xe1\xe7\xe5\xe4"); // inverse "damaged"
   } else {
      cputs("fine");
   }
   // cputs("\nship for one with 50 more capacity by\npaying an additional ");
	print_msg(M_ship_for_one);
	cprintuchar(50);
	print_msg(M_more_capacity);
	cprintfancy(amount);
	cprint_taipan_prompt();

	if(yngetc(0) == 'y') {
      cash -= amount;
		cash_dirty = 1;
      hold += 50;
      capacity += 50;
      damage = 0;
	}

	port_stats();
   if(one_chance_in(2))
      new_gun();

   return;
}

void new_gun(void) {
   unsigned int amount;

	if(guns >= 1000) return;

   amount = gunamt() + 500;

   if(cash < amount) return;

	compradores_report();
   // cputs("Do you wish to buy a ship's gun\nfor ");
	print_msg(M_gun_offer);
	cprintfancy(amount);
	cprint_taipan_prompt();

	if(yngetc(0) == 'y') {
		if(hold < 10) {
			print_msg(M_overburdened);
			bad_joss_timed_getch();
			return;
		}
      cash -= amount;
		cash_dirty = 1;
      hold -= 10;
      guns += 1;
	}

   port_stats();
}

/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/

/* cprintfancy_centered() does this for 0 to 999999:
	|   999999   |
	|   99999    |
	|    9999    |
	|    999     |
	|     99     |
	|     9      | */

#if 0
void cprintfancy_centered(unsigned long num) {
	if(num < 1000000L) {
		cspaces(3);
		if(num < 100L) cspace();
		if(num < 10000L) cspace();
		rvs_on();
		cprintulong(num);
	} else {
		rvs_on();
		cprintfancy(num);
	}
	rvs_off();
}
#else
// saves 12 bytes:
void cprintfancy_centered(unsigned long num) {
	if(num < 1000000L) {
		cspaces(3);
		if(num < 100L) cspace();
		if(num < 10000L) cspace();
	}
	rvs_on();
	cprintfancy(num);
	rvs_off();
}
#endif

/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/

/* if BIGNUM, cprintfancy() just converts to bignum and uses
	cprintfancy_big() to do the work. A bit slower, but fast
	enough, and avoids duplicate logic. */
#ifdef BIGNUM
/*
# ifdef CART_TARGET
#  pragma code-name (push, "HIGHCODE")
# endif
*/
void cprintfancy(unsigned long num) {
	bignum(b);
	ulong_to_big(num, b);
	cprintfancy_big(b);
}
/*
# ifdef CART_TARGET
#  pragma code-name (pop)
# endif
*/
#else
/* replaces old fancy_numbers. same logic, but stuff is just
	printed on the screen rather than being kept in a buffer.
	One minor difference between this and fancy_numbers() is that
	we print "1.10 Million" rather than "1.1 Million" (extra zero).
	I don't think anyone's going to complain.
 */
void cprintfancy(unsigned long num) {
	unsigned char tmp;

	if(num >= 100000000L) {
		/* 100 million and up:
			|1000 Million|
			|100 Million |  */
		cprintulong(num / 1000000L);
   } else if (num >= 10000000L) {
		/* 10 million to 99 million:
			| 10 Million |
			|10.1 Million|*/
		tmp = (num % 1000000L) / 100000L;
		cprintulong(num / 1000000L);
		if(tmp) {
			// cputc('.');
			cprint_period();
			cprintulong(tmp);
		}
   } else if (num >= 1000000L) {
		/* 1 million to 9 million:
			| 1 Million  |
			|1.10 Million| // always has 0, never 1.1
			|1.23 Million| */
		tmp = (num % 1000000L) / 10000L;
		cprintulong(num / 1000000L);
		if(tmp) {
			// cputc('.');
			cprint_period();
			if(tmp < 10L) cputc0();
			cprintulong(tmp);
		}
   } else {
		/* 0 to 999999:
			|   999999   |
			|   99999    |
			|    9999    |
			|    999     |
			|     99     |
			|     9      | */

		cprintulong(num);
		return;
	}

	cputs(" Million");
}
#endif

/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/
void justify_int(unsigned int num) {
	if(num < 1000) cspace();
	if(num <  100) cspace();
	if(num <   10) cspace();
	cprintuint(num);
}

void update_guns(void) {
	rvs_on();
	gotoxy(31, 1);
	justify_int(guns);
	gotox(39);
	cblank(1);
	pluralize(guns);
	rvs_off();
}

char orders = 0;
extern void set_orders(void);
/*
void set_orders(void) {
	switch(timed_getch()) {
		case 'f': orders = 1; break;
		case 'r': orders = 2; break;
		case 't': orders = 3; break;
		default: break;
	}
}
*/

void fight_stats(int ships) {
	char status = get_ship_status();
	gotox0y(5);
	clrtoeol();

	// cputs("Current seaworthiness: ");
	print_msg(M_cur_seaworth);
	print_status_desc(status);
	cputs(" (");
	cprintuchar(status);
	cputs("%)");

   gotox0y(0);

	justify_int(ships);
	// cputs(" ship");
	print_msg(M_space_ship);
	// if(ships != 1) cputc_s();
	pluralize(ships);
	// cputs(" attacking");
	print_msg(M_space_attacking);

	// cputs("Your orders are: ");
	print_msg(M_your_orders_are);
	cblank(11);
	switch(orders) {
		/*
		case 1: cputs("Fight"); break;
		case 2: cputs("Run"); break;
		case 3: cputs("Throw Cargo"); break;
		*/
		case 1: print_msg(M_fight); break;
		case 2: cputs("Run"); break;
		case 3: print_msg(M_throw); break;
		default: break;
	}

}

/* print an inverse video plus if there are offscreen ships,
	or clear it to a space if not. */
extern void plus_or_space(unsigned char b);
/*
void plus_or_space(unsigned char b) {
	gotoxy(39, 15);
	cputc(b ? 0xab : ' ');
	// hide_cursor();
}
*/

/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/

/* sea_battle only ever returns 1 to 4. making the
	return type a char saved 61 bytes! */
char sea_battle(char id, int num_ships) {
	/* These locals seem to eat too much stack and
		cause weird behaviour, so they're static now. */
	static int time,
				  s0,
				  ok,
				  ik,
				  i;
				  // input,
	char choice, flashctr, num_on_screen;
	unsigned long amount, total;

	port_stat_dirty = 1;
	ik = 1;

	ok = 0;
	turbo = 0;
	orders = 0;
	num_on_screen = 0;

	time = get_time();
	s0 = num_ships;

	/* This calculation was different in the Apple and Linux ports. I went
		with the Apple version. */
	booty = randlmod((long)(time / 4L * 1000L * num_ships)) + (long)(randi()%1000 + 250);

	/* Not ideal, but better than 'booty = 0L' I think. */
	while(would_overflow(cash, booty)) {
		booty >>= 1;
	}

	clear_ships_on_screen();
	clr_screen();

	/* the static part of "we have N guns" display, gets printed
		only once per battle. Bloats the code by 30-odd bytes, but
		updates are smoother-looking. Maybe. */
	rvs_on();
	gotox(30);
	// cputs("   We have");
	print_msg(M_we_have);
	gotoxy(30, 1);
	cspaces(6);
	cputs("gun");
	// rvs_off(); // redundant
	update_guns();

	while(num_ships > 0) {
		fight_stats(num_ships);
		if(damage >= capacity) return 4;

		// status = get_ship_status();
		/* // I think this is a problem:
			if(status <= 0) {
			return 4;
			}
		 */

		for(i = 0; i <= 9; i++) {
			if (num_ships > num_on_screen) {
				if (ships_on_screen[i] == 0) {
					tjsleep(5);
					ships_on_screen[i] = (randi() % ec) + 20;
					draw_lorcha(i);
					num_on_screen++;
				}
			}
		}

		plus_or_space(num_ships > num_on_screen);

		// gotox0y(16);
		// cputs("\n");
		// crlf();

		set_orders();

		if(orders == 0) {
			set_orders();
			if(!orders) {
				turbo = 0;
				gotox0y3_clrtoeol();
				// cputs("what shall we do??\n(Fight, Run, Throw cargo)");
				print_msg(M_what_shall_we_do);
				under_attack_sound();

				while(!orders) set_orders();

				gotox0y3();
				cblank(80); /* clears 2 lines */
			}
		}

		fight_stats(num_ships);
		if((orders == 1) && (guns > 0)) {
			static int targeted, sk;
			sk = 0;

			ok = 3;
			ik = 1;
			// cputs("Aye, we'll fight 'em");
			print_combat_msg(M_aye_fight);
			set_orders();

			// cputs("We're firing on 'em");
			print_combat_msg(M_were_firing);
			set_orders();

			for(i = 1; i <= guns; i++) {
				if(no_ships_on_screen()) {
					static int j;

					for (j = 0; j <= 9; j++) {
						if (num_ships > num_on_screen) {
							if(ships_on_screen[j] == 0) {
								ships_on_screen[j] = randlmod(ec) + 20;
								draw_lorcha(j);
								num_on_screen++;
							}
						}
					}
				}

				plus_or_space(num_ships > num_on_screen);

				// gotox0y(16);
				// crlf();

				do {
					targeted = randi()%10;
				} while(ships_on_screen[targeted] == 0);

				/* flash_lorcha must be called an even number of times
					to leave the lorcha in an unflashed state after. */
				for(flashctr = 0; flashctr < 6; flashctr++) {
					flash_lorcha(targeted);
					tjsleep(2);
				}

				damage_lorcha(targeted);

				ships_on_screen[targeted] -= randi()%30 + 10;

				if(ships_on_screen[targeted] <= 0) {
					num_on_screen--;
					num_ships--;
					sk++;
					ships_on_screen[targeted] = 0;

					bad_joss_sound(); /* not sure this should be here */
					if(turbo)
						clear_lorcha(targeted);
					else
						sink_lorcha(targeted);

					plus_or_space(num_ships > num_on_screen);

					fight_stats(num_ships);
				}

				if(num_ships == 0) {
					i += guns;
				} else {
					tjsleep(10);
				}
			}
			if(sk > 0) {
				// cputs("Sunk ");
				print_combat_msg(M_sunk);
				cprintuint(sk);
				// cputs(" of the buggers");
				print_msg(M_of_the_buggers);
				if(!turbo) bad_joss_sound();
			} else {
				// cputs("Hit 'em, but didn't sink 'em");
				print_combat_msg(M_didnt_sink);
			}
			set_orders();

			// if ((randi()%s0 > (num_ships * .6 / id)) && (num_ships > 2))
			if((randi()%s0 > ((num_ships / 2) / id)) && (num_ships > 2)) {
				static int ran;
				// ran = randi()%(num_ships / 3 / id) + 1;
				ran = randlmod(num_ships / 3 / id) + 1;

				num_ships -= ran;
				fight_stats(num_ships);
				gotox0y3_clrtoeol();
				cprintuint(ran);
				// cputs(" ran away");
				print_msg(M_ran_away);
				bad_joss_sound();

				if(num_ships <= 10) {
					for(i = 9; i >= 0; i--) {
						if ((num_on_screen > num_ships) && (ships_on_screen[i] > 0)) {
							ships_on_screen[i] = 0;
							num_on_screen--;

							clear_lorcha(i);
							tjsleep(5);
						}
					}
					if(num_ships == num_on_screen) {
						plus_or_space(0);
					}
				}

				// gotox0y(16);

				set_orders();
			}
		} else if ((orders == 1) && (guns == 0)) {
			// cputs("We have no guns");
			print_combat_msg(M_we_have_no_guns);
			bad_joss_sound();
			turbo = 0;
			orders = 0;
			set_orders();
		} else if (orders == 3) {
			choice = 0;
			amount = 0;
			total = 0;
			turbo = 0;

			if(hold_is_empty()) {
				print_combat_msg(M_you_have_no_cargo);
				bad_joss_sound();
				orders = 0;
				set_orders();
			} else {
				// cputs("You have the following on board");
				print_combat_msg(M_you_have_on_board);
				cprint_colon_space();
				gotoxy(4, 4);
				// cputs(item[0]);
				print_item(0);
				// cputs(": ");
				cprint_colon_space();
				cprintulong(hold_[0]);
				gotoxy(24, 4);
				// cputs(item[1]);
				print_item(1);
				// cputs(": ");
				cprint_colon_space();
				cprintulong(hold_[1]);
				gotox0y(5);
				clrtoeol();
				gotox(5);
				// cputs(item[2]);
				print_item(2);
				// cputs(": ");
				cprint_colon_space();
				cprintulong(hold_[2]);
				gotoxy(21, 5);
				// cputs(item[3]);
				print_item(3);
				// cputs(": ");
				cprint_colon_space();
				cprintulong(hold_[3]);

				gotox0y(6);
				clrtoeol();
				// cputs("What shall I throw overboard");
				print_msg(M_what_shall_i_throw);
				cprint_taipan_prompt();

				choice = get_item_battle();

				if(choice < 4) {
					gotox0y(6);
					clrtoeol();
					// cputs("How much");
					print_msg(M_how_much);
					cprint_taipan_prompt();

					amount = get_num();
					if((hold_[choice] > 0) && ((amount == UINT32_MAX) || (amount > hold_[choice])))
					{
						amount = hold_[choice];
					}
					total = hold_[choice];
				} else {
					total = hold_[0] + hold_[1] + hold_[2] + hold_[3];
				}

				gotox0y(4);
				cblank(120);

				if(total > 0) {
					// cputs("Let's hope we lose 'em");
					print_combat_msg(M_hope_we_lose_em);
					bad_joss_sound();
					if (choice < 4) {
						hold_[choice] -= amount;
						hold += amount;
						ok += (amount / 10);
					} else {
						clear_hold();
						hold += total;
						ok += (total / 10);
					}

					set_orders();
				} else {
					// cputs("There's nothing there");
					print_combat_msg(M_nothing_there);
					good_joss_sound();

					set_orders();
				}
			}
		}

		if((orders == 2) || (orders == 3)) {
			if(orders == 2) {
				// cputs("Aye, we'll run");
				print_combat_msg(M_aye_run);
				set_orders();
			}

			ok += ik++;
			if(randi()%ok > randi()%num_ships) {
				// cputs("We got away from 'em");
				print_combat_msg(M_we_got_away);
				good_joss_sound();
				/* don't use set_orders() here! it allows changing from Run
					to Fight, *after* getting away, so you end up getting booty
					when you ran. */
				timed_getch();
				num_ships = 0;
			} else {
				// cputs("Couldn't lose 'em.");
				print_combat_msg(M_couldnt_lose_em);
				set_orders();

				if((num_ships > 2) && (one_chance_in(5))) {
					static int lost;
					lost = (randi()%num_ships / 2) + 1;

					num_ships -= lost;
					fight_stats(num_ships);
					// cputs("But we escaped from ");
					print_combat_msg(M_but_we_escaped);
					cprintuint(lost);
					// cputs(" of 'em!");
					print_msg(M_of_em);

					if(num_ships <= 10) {
						for(i = 9; i >= 0; i--) {
							if((num_on_screen > num_ships) && (ships_on_screen[i] > 0)) {
								ships_on_screen[i] = 0;
								num_on_screen--;

								clear_lorcha(i);
								tjsleep(5);
							}
						}
						plus_or_space(num_ships > num_on_screen);
					}

					// gotox0y(16);

					set_orders();
				}
			}
		}

		if(num_ships > 0) {
			// cputs("They're firing on us");
			print_combat_msg(M_theyre_firing);

			set_orders();
			if(!turbo) explosion();

			fight_stats(num_ships);
			plus_or_space(num_ships > num_on_screen);

			// cputs("We've been hit");
			print_combat_msg(M_weve_been_hit);
			under_attack_sound();

			set_orders();

			i = (num_ships > 15) ? 15 : num_ships;

			// is this really correct?
			// if ((guns > 0) && ((randi()%100 < (((float) damage / capacity) * 100)) ||
			// ((((float) damage / capacity) * 100) > 80)))

			if((guns > 0) && ((randi()%100 < ((damage * 100L) / capacity)) ||
						(((damage * 100L) / capacity)) > 80))
			{
				i = 1;
				guns--;
				hold += 10;
				fight_stats(num_ships);
				// cputs("The buggers hit a gun");
				print_combat_msg(M_buggers_hit_gun);
				if(!turbo) under_attack_sound();
				fight_stats(num_ships);
				update_guns();

				set_orders();
			}

			// damage = damage + ((ed * i * id) * ((float) randi() / RAND_MAX)) + (i / 2);
			// remember, ed is now scaled by 2 (used to be 0.5, now 1)

			// broken because sometimes works out to 0 or 1. If it's 0,
			// randi()%0 is just randi() (ouch)... on a modern platform,
			// this would trigger a floating point exception or similar.
			// cc65 runtime can't detect it...
			// If ((ed * i * id)/2)) works out to 1, anything%1 is 0.
			// damage = damage + (randi() % ((ed * i * id)/2)) + (i / 2);
			// The answer is to avoid to % operator if the 2nd arg would be
			// 0 or 1: the intended result would just be 0 or 1 anyway.

			newdamage = ((ed * i * id)/2) + (i / 2);
			if(newdamage <= 0) newdamage = 1; // how the hell could this happen?
			if(newdamage > 1)
				newdamage = randi() % newdamage;
			damage += newdamage;
			if(damage > capacity) damage = capacity; /* just in case */

			/* the above is still somehow broken. When fighting lots of
				ships, late in the game, we still get ship status over 100%
				in the fight screen, and mchenry says we're 4 billion percent
				damaged (and memory gets all kinds of corrupted after that).
				I do NOT understand what's going on here. It looks like
				damage is still somehow going negative, but that shouldn't
				be possible. */
			if(damage < 0) damage = capacity; /* band-aid! */

			if(damage == capacity) return 4;

#ifdef DAMAGE_TEST
			gotox0y(23);
			clrtoeol();
			cprintulong(ed);
			cspace();
			cprintulong(i);
			cspace();
			cprintulong(id);
			cspace();
			cprintulong(damage);
			cspace();
			cprintulong(newdamage);
			cgetc();
#endif

			if((id == GENERIC) && (one_chance_in(20))) {
				return 2;
			}
		}
	}

	if(orders == 1) {
		fight_stats(num_ships);
		// cputs("We got 'em all");
		print_combat_msg(M_we_got_em_all);
		bad_joss_timed_getch();

		return 1;
	} else {
		return 3;
	}
}

/* TODO: rewrite in asm. Maybe. */
unsigned long get_num(void) {
	unsigned char count = 0;
   unsigned char input, i;

	SET_HELP(get_amount_help);
   while((input = numgetc()) != '\n') {
		if(input == BKSP) {
			if(!count) continue;
			backspace();
         count--;
		} else if(input == 'a') {
			if(!count) {
				return UINT32_MAX;
			}
		} else if(input == 'k' || input == 'm') {
			for(i = 0; i < (input == 'k' ? 3 : 6); i++) {
				cputc(num_buf[count++] = '0');
				if(count >= 10) break;
			}
		} else if(input == DEL) {
			while(count) {
				backspace();
				count--;
			}
		} else {
			if(count >= 10) continue;
         cputc(num_buf[count++] = input);
		}
	}

	CLEAR_HELP;
	num_buf[count] = '\0';
	return strtonum(num_buf);
}

/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/
void set_prices(void) {
	unsigned char i;
	for(i = 0; i < 4; ++i)
		price[i] = (base_price[i][port] * rand1to3() * base_price[i][0]) / 2;
}

unsigned int warehouse_in_use() {
   return hkw_[0] + hkw_[1] + hkw_[2] + hkw_[3];
}
/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/


void port_stats(void) {
	unsigned char i, status = get_ship_status();
	int in_use;
#ifdef PORT_STAT_TIMER
	int startframe, startline, endframe, endline;
#endif

	if(port_stat_dirty) {
		/* this stuff takes approx 1 jiffy */
		bank_dirty = cash_dirty = 1;

		/* all the static text that used to be in port_stats() has
			been moved to mkportstats.c, which creates a .xex file which
			will get prepended to taipan.xex and loaded into a chunk of memory
			cc65 won't use. When it's time to print it, it'll get copied
			into *SAVMSC. */
		redraw_port_stat();
		gotox0y(15);
		chline(40);

		gotox0y(0);
		clrtoeol();
		if(firmpos) cspaces(firmpos);
		// cputs("Firm: ");
		cprint_firm_colon();
		cputs(firm);
		comma_space();
		// cputs(location[1]);
		print_location(1);
	}

	/* dynamic stuff: */

	/* approx 73 VCOUNTs */
	gotoxy(21, 4);
	in_use = warehouse_in_use();
	cprintuint(in_use);
	cblankto(26);
	gotoxy(21, 6);
	cprintuint(10000 - in_use);
	cblankto(26);


	/* approx 1 jiffy */
	for(i = 0; i < 4; ++i) {
		gotoxy(12, i + 3);
		cprintuint(hkw_[i]);
		cblankto(18);
	}

	gotoxy(7, 8);
   if(hold >= 0) {
		cprintulong(hold);
		cblankto(15);
   } else {
		cputs("\xcf\xf6\xe5\xf2\xec\xef\xe1\xe4"); // inverse "Overload"
   }

	gotoxy(22, 8);
	cprintuint(guns);
	cblankto(27);

	for(i = 0; i < 4; ++i) {
		gotoxy(12, i + 9);
		cprintulong(hold_[i]);
		cblankto(21);
	}

	gotoxy(32, 3);
   // cputs(months + 4 * (month - 1));
	print_month();
	cspace();
	cprintuint(year);

	gotoxy(30, 6);
	if(port == 4 || port == 5) cspace();
	rvs_on(); 
	// cputs(location[port]); 
	print_location(port);
	rvs_off(); 
	clrtoeol();

#ifdef PORT_STAT_TIMER
	startframe = PEEK(20);
	startline = PEEK(54283U);
#endif

	/* approx 1.5 frames */
	gotoxy(28, 9);
	cprintfancy_centered(debt);
	clrtoeol();

#ifdef PORT_STAT_TIMER
	endframe = PEEK(20);
	endline = PEEK(54283U);
#endif

	/* approx 1/4 frame */
	gotoxy(29, 12);
	clrtoeol();
	print_status_desc(status);
	cputc(':');
	cprintuint(status);

	if(cash_dirty) {
		/* approx 1.5 frames */
		gotoxy(6, 14);
		cprintfancy(cash);
		cblankto(20);
		cash_dirty = 0;
	}

	if(bank_dirty) {
		gotoxy(26, 14);
#ifdef BIGNUM
		cprintfancy_big(bank);
#else
		cprintfancy(bank);
#endif
		clrtoeol();
		bank_dirty = 0;
	}

#ifdef PORT_STAT_TIMER
	gotoxy(0, 15);
	cprintuint(startframe);
	cprint_pipe();
	cprintuint(startline);
	cspace();
	cprintuint(endframe);
	cprint_pipe();
	cprintuint(endline);
	clrtoeol();
#endif

	port_stat_dirty = 0;
}

void mchenry(void) {
	compradores_report();
	/*
	cputs("Mc Henry from the Hong Kong\n"
			"Shipyards has arrived!! He says, 'I see\n"
			"ye've a wee bit of damage to yer ship.'\n"
			"Will ye be wanting repairs? ");
			*/
	print_msg(M_mchenry_has_arrived);

	if(yngetc('y') == 'y') {
		static unsigned int percent, time;
		static unsigned long br, repair_price, amount;
		percent = (damage * 100L / capacity);
		time = get_time();

		/*
			long br = ((((60 * (time + 3) / 4) * (float) randi() / RAND_MAX) +
			25 * (time + 3) / 4) * capacity / 50),
			repair_price = (br * damage) + 1,
			amount;
		 */

		/* the calculations below can & will overflow, but you'd have to
			play a *long* time (like, year 2000 or later), and have a ship
			capacity over maybe 10,000. */
		br = ((randlmod(60 * (time + 3) / 4) + 25 * (time + 3) / 4) * capacity / 50);
		repair_price = (br * damage) + 1;

		clear_msg_window();
		// cputs("Och, 'tis a pity to be ");
		print_msg(M_tis_a_pity);
		cprintuint(percent);
		// cputs("% damaged.\nWe can fix yer whole ship for ");
		print_msg(M_percent_damaged);
		cprintulong(repair_price);
		gotoy(19); /* in case last digit printed at (39, 19) */
		// cputs("\nor make partial repairs if you wish.\n");
		print_msg(M_or_partial_repairs);
		how_much();
		// cputs("will ye spend? ");
		print_msg(M_will_ye_spend);

		for (;;) {
			gotoxy(24, 21);
			amount = get_num();
			if(amount == UINT32_MAX) {
				if(cash > repair_price)
					amount = repair_price;
				else
					amount = cash;
			}
			if(amount <= cash) {
				cash -= amount;
				cash_dirty = 1;
				// damage -= (int)((amount / br) + .5);
				damage -= (int)(amount / br);
				damage = (damage < 0) ? 0 : damage;
				port_stats();
				break;
			}
		}
	}

	return;
}

/*
void retire_blanks(void) {
	char i;
	for(i = 0; i < 29; ++i) cspace();
	crlf();

	// above loop saves a measly 6 bytes over this:
   // cputs("                             \n");
}
*/

void retire_blanks(void) {
	cspaces(29);
	crlf();
}

#ifdef BIGNUM
void aire(void) {
	char endspace = 1;
	bignum(networth);
	bignum(big1T) = BIG_1T;

	ulong_to_big(cash, networth);
	big_add(networth, networth, bank);

	// cputs("    ");
	cspaces(4);
	if(big_cmp(networth, big1B) < 0) {
		cputc('M');
	} else if(big_cmp(networth, big1T) < 0) {
		cputc('B');
	} else {
		cputs("T R");
		endspace = 0;
	}
	// cputs(" I L L I O N A I R E !");
	print_msg(M_illionaire);
	if(endspace) cspaces(2);
	crlf();
}
#endif

void retire(void) {
	compradores_report();

	print_msg(M_confirm_retire);
	if(yngetc('n') != 'y')
		return;

	crlf();

	rvs_on();
	// cspaces(29);
	// crlf();
	retire_blanks();

   // cputs("    Y o u ' r e    a");
	print_msg(M_youre_a);
	cspaces(9);
	crlf();

	// cspaces(29);
	// crlf();
	retire_blanks();
#ifdef BIGNUM
	aire();
#else
   cputs("    M I L L I O N A I R E !  \n");
#endif
	// cspaces(29);
	// crlf();
	retire_blanks();
	rvs_off();
   timed_getch();

   final_stats();
}

extern void __fastcall__ print_score_msg(long score);

long score_lim[] = {
	50000L,
	8000L,
	1000L,
	500L,
	((long) 0x80000000)
};

const char const *score_msg[] = {
	M_ma_tsu,
	M_master_taipan,
	M_taipan,
	M_compradore,
	M_galley_hand
};

const char const *score_desc[] = {
	"50,000 and over |\n|",
   " 8,000 to 49,999|\n|",
	" 1,000 to  7,999|\n|",
	"   500 to    999|\n|",
	"   less than 500|\n"
};

void final_stats(void) {
	char i, unrated = 1;
	int years = year - 1860;

#ifdef BIGNUM
	long score;
	bignum(finalcash);
	bignum(big_100) = BIG_100;
	bignum(bigscore);
	bignum(bigtmp);

	ulong_to_big(cash, finalcash);
	ulong_to_big(debt, bigtmp);
	big_add(finalcash, finalcash, bank);
	big_sub(finalcash, finalcash, bigtmp);

	big_div(bigscore, finalcash, big_100);
	ulong_to_big((unsigned long)get_time(), bigtmp);
	big_div(bigscore, bigscore, bigtmp);

	if(big_cmp(bigscore, big1B) > 0) {
		score = 1000000000L;
	} else if(big_cmp(bigscore, big0) < 0) {
		score = -1;
	} else {
		big_to_ulong(bigscore, (unsigned long*)&score);
	}

#else
	/* TODO: write cprintlong() to print signed value */
	long finalcash = cash + bank - debt;
	long score = finalcash / 100 / get_time();
#endif

	port_stat_dirty = 1;

   clr_screen();
   // cputs("Your final status:\n\n"
			// "Net cash:  ");
	print_msg(M_your_final_status);
#ifdef BIGNUM
	cprintfancy_big(finalcash);
#else
	cprintfancy(finalcash);
#endif
	// cputs("\nShip size: ");
	print_msg(M_ship_size);
	cprintulong(capacity);
	// cputs(" units with ");
	print_msg(M_units_with);
	cprintuint(guns);
	// cputs(" guns\n\n"
			// "You traded for ");
	print_msg(M_you_traded_for);
	cprintuint(years);
	// cputs(" year");
	print_msg(M_spc_year);
	pluralize(years);
   // if (years != 1) cputc_s();
   // cputs(" and ");
	print_msg(M_spc_and_spc);

   /* if you retire in e.g. december 1870, that's 9 years and 11 months,
      not 9 years and 12 months. If you retire in january 1861, it should
      read 1 year and 0 months (not 1 year and 1 month!). */
	month--;

	cprintuchar(month);
	// cputs(" month");
	print_msg(M_spc_month);
	pluralize(month);
   // if (month > 1) cputc_s();
	crlf();
	crlf();
	rvs_on();
	// cputs("Your score is ");
	print_msg(M_your_score_is);
#ifdef BIGNUM
	cprintfancy_big(bigscore);
#else
	cprintulong(score);
#endif
	cprint_period();
	crlf();
	rvs_off();

	/* 8969 bytes with this stuff:
	if(score < 0)
      // cputs("The crew has requested that you stay on\n"
				// "shore for their safety!!\n\n");
		print_msg(M_stay_on_shore);
	else if(score < 100)
      // cputs("Have you considered a land based job?\n\n\n");
		print_msg(M_land_based_job);
		*/

	/* Optimized the above stanza, only saved 5 bytes (8874).
		Compiled code is 45 bytes. Replacing with a function call costs
		3 bytes, so the asm function has to be <42 bytes (it is). */
	print_score_msg(score);

   // cputs("Your Rating:\n");
	gotox0y(11);
	print_msg(M_your_rating);
	cputc(17); // upper left corner
	chline(31);
	cputc(5); // upper right corner
	crlf();
	cprint_pipe();

	for(i = 0; i < 5; i++) {
		if(unrated && score >= score_lim[i]) {
			unrated = 0;
			rvs_on();
		}
		print_msg(score_msg[i]);
		rvs_off();
		gotox(16);
		cputs(score_desc[i]);
	}

	cputc(26); // lower left corner
	chline(31);
	cputc(3); // lower right corner

	gotox0y22();
	// cputs("Play again? ");
	print_msg(M_play_again);

#ifdef FINAL_STATS_TEST
	agetc();
	clr_screen();
	return;
#endif

	if(yngetc('y') == 'y') {
		init_game();
		return;
	}

	/* player said No, don't play again...
		for the xex build, exit(0) gets us back to DOS.
		for the cartridge, reboot the Atari (gets us back to the title screen). */

#ifdef CART_TARGET
	__asm__("jmp $e477"); /* COLDSV, coldstart vector */
#else
	/* exit(0) works by itself in DOS 2.0S or 2.5, or any DUP.SYS
		style DOS that reopens the E: device when entering the menu.
		However, command-line DOSes (XL and Sparta) don't do this,
		which results in garbage on screen and wrong colors. So: */

	/* restore CHBAS to its original value, generally the ROM font.
		This is called fontsave in newtitle.s. */
	POKE(756, PEEK(0xcc));

	/* restore COLOR1 and COLOR2. These locations are called
		color1save and color2save in newtitle.s. */
	POKE(709, PEEK(0xcd));
	POKE(710, PEEK(0xce));
	exit(0);
#endif
}

/*
	// rewritten in asm (arrayutils.s)
char have_no_cargo(void) {
	char i;
	for(i = 0; i < 4; ++i)
		if(hkw_[i] || hold_[i]) return 0;
	return 1;
}
*/

/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/
void you_have_only(void) {
	// cputs("You have only ");
	print_msg(M_you_have_only);
}
/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/


void transfer(void) {
   int i, in_use;
   unsigned long amount = 0;

	if(have_no_cargo()) {
      gotox0y22();
      clrtobot();
      // cputs("You have no cargo");
		print_msg(M_you_have_no_cargo);
		good_joss_timed_getch();
      return;
   }

   for(i = 0; i < 4; i++) {
      if(hold_[i] > 0) {
         for (;;) {
				compradores_report();
				how_much();
				// cputs(item[i]);
				print_item(i);
				// cputs(" shall I move\nto the warehouse");
				print_msg(M_move_to_whouse);
				cprint_taipan_prompt();

            amount = get_num();
            if(amount == UINT32_MAX)
               amount = hold_[i];

            if(amount <= hold_[i]) {
               // in_use = hkw_[0] + hkw_[1] + hkw_[2] + hkw_[3];
					in_use = warehouse_in_use();
               if((in_use + amount) <= 10000) {
                  hold_[i] -= amount;
                  hkw_[i] += amount;
                  hold += amount;
                  break;
               } else if(in_use == 10000) {
                  gotox0y(21);
                  // cputs("Your warehouse is full");
						print_msg(M_whouse_full);
						good_joss_timed_getch();
               } else {
                  gotox0y(21);
                  // cputs("Your warehouse will only hold an\nadditional ");
						print_msg(M_whouse_only_hold);
						cprintuint(10000 - in_use);
						cprint_taipan_bang();
						good_joss_timed_getch();
               }
            } else {
					clear_msg_window();
               // gotox0y(18);
               // clrtobot();
					you_have_only();
					cprintulong(hold_[i]);
               // cputs(", Taipan.\n");
					cprint_taipan_period();
					good_joss_timed_getch();
            }
         }
         port_stats();
      }

      if(hkw_[i] > 0) {
         for(;;) {
				compradores_report();
				how_much();
				// cputs(item[i]);
				print_item(i);
				// cputs(" shall I move\naboard ship");
				print_msg(M_move_aboard);
				cprint_taipan_prompt();

            amount = get_num();
            if(amount == UINT32_MAX)
               amount = hkw_[i];

            if(amount <= hkw_[i]) {
               hold_[i] += amount;
               hkw_[i] -= amount;
               hold -= amount;
               break;
            } else {
					clear_msg_window();
               // gotox0y(18);
               // clrtobot();
					you_have_only();
					cprintuint(hkw_[i]);
					cprint_taipan_period();
					// cputs("\n");
					crlf();
               good_joss_timed_getch();
            }
         }
         port_stats(); // have to do this in the loop
      }
   }

   return;
}

unsigned char choose_port(void) {
	unsigned char choice;

	compradores_report();
	cprint_taipan_comma();
	do_you_wish();
   // cputs("me to go to:\n");
	print_msg(M_me_to_go_to);

	for(choice = 1; choice < 8; ++choice) {
		if(choice == 7) crlf();
		if(choice == port)
			cputc(choice + '0');
		else
			cputc(choice + 0xb0);  // inverse number
		cputs(") ");
		// cputs(location[choice]);
		print_location(choice);
		if(choice != 7) comma_space();
	}
	cprint_question_space();

	/*
   cputs("1) Hong Kong, 2) Shanghai, 3) Nagasaki,\n"
			"4) Saigon, 5) Manila, 6) Singapore, or\n"
			"7) Batavia ? ");
			*/

   for (;;) {
      gotoxy(12, 21);
      clrtobot();

      choice = numgetc() - '0';

      if(choice == port) {
         // cputs("\n\nYou're already here");
			print_msg(M_already_here);
			good_joss_timed_getch();
      } else if(choice <= 7) {
			return choice;
      } else { /* backspace, enter, etc */
			return 0;
		}
   }
}

void quit(void) {
#ifdef BIGNUM
	bignum(banktmp);
#endif
	unsigned char result = 0, sunk;
   int damagepct;

	at_sea();
	captains_report();

#ifdef COMBAT_TEST
   if(1)
#else
   if(one_chance_in(bp))
#endif
   {
      int num_ships = randi()%((capacity / 10) + guns) + 1;

      if (num_ships > 9999)
      {
         num_ships = 9999;
      }
		cprintuint(num_ships);
      // cputs(" hostile ship");
		print_msg(M_hostile_ship);
		pluralize(num_ships);
		// if(num_ships != 1) cputc_s();
      // cputs(" approaching");
		print_msg(M_approaching);
		under_attack_timed_getch();

      result = sea_battle(GENERIC, num_ships);
   }

   if(result == 2) {
      port_stats();
		at_sea();

		captains_report();
		// cprint_li_yuen();
      // cputs("'s fleet drove them off!");
		print_msg(M_fleet_drove_off);

      timed_getch();
   }

   if(((result == 0) && (randi()%(4 + (8 * li))) == 0) || (result == 2)) {
		clear_msg_window();
		// cprint_li_yuen();
      // cputs("'s pirates");
		print_msg(M_s_pirates);
		bad_joss_timed_getch();

      if(li > 0) {
         // cputs("Good joss!! They let us be!!\n");
			print_msg(M_they_let_us_be);
			bad_joss_timed_getch();

         // return; // original code, results in prices not changing.
			result = 0;
      } else {
         static int num_ships;
         num_ships = randi()%((capacity / 5) + guns) + 5;

			cprintuint(num_ships);
			/* "ships" will always be plural (at least 5 of them) */
         // cputs(" ships of Li Yuen's pirate\nfleet");
			print_msg(M_ships_of_fleet);
			under_attack_timed_getch();

			/* WTF, the original code reads:
				sea_battle(LI_YUEN, num_ships);
				...which seems to mean you die if you succeed in
				running away from li yuen's pirates... */
         result = sea_battle(LI_YUEN, num_ships);
      }
   }

   if(result > 0) {
      port_stats();
		at_sea();

		captains_report();
      if(result == 1) {
         // cputs("We captured some booty.\n"
					// "It's worth ");
			print_msg(M_captured_some_booty);
			cprintfancy(booty);
			cprint_bang();
         cash += booty;
			cash_dirty = 1;
			good_joss_timed_getch();
      } else if (result == 3) {
         // cputs("We made it!");
			print_msg(M_we_made_it);
			good_joss_timed_getch();
      } else {
         // cputs("The buggers got us");
			print_msg(M_buggers_got_us);
         // cputs("!\nIt's all over, now!!!");
			print_msg(M_all_over_now);
			under_attack_timed_getch();

         final_stats();
         return;
      }
   }

   if(one_chance_in(10)) {
		clear_msg_window();
      // cputs("Storm");
		print_msg(M_storm);
		bad_joss_timed_getch();

      if(one_chance_in(30)) {
         // cputs("   I think we're going down!!\n\n");
			print_msg(M_think_going_down);
         timed_getch();

         // if (((damage / capacity * 3) * ((float) randi() / RAND_MAX)) >= 1)
			// in the float version, damage/capacity*3 is your damage percentage,
			// scaled 0 (0%) to 3 (100%). So if you're less than 34% damaged,
			// you have no chance of sinking. If you're 34%-66% damaged, you
			// have a 1 in 3 chance. If you're over 66%, you have a 2 in
			// 3 chance.
			damagepct = damage * 100L / capacity;
			if(damagepct < 34)
				sunk = 0;
			else if(damagepct < 67)
				sunk = randlmod(3) == 0;
			else
				sunk = randlmod(3) != 0;

         if(sunk) {
            // cputs("We're going down");
				print_msg(M_were_going_down);
				under_attack_timed_getch();

            final_stats();
				return;
         }
      }

      // cputs("    We made it!!\n\n");
		print_msg(M_storm_we_made_it);
		bad_joss_timed_getch();

      if(one_chance_in(3)) {
         int orig = port;

			while(port == orig)
				port = randi()%7 + 1;

			clear_msg_window();
         // cputs("We've been blown off course\nto ");
			print_msg(M_blown_off_course);
         // cputs(location[port]);
			print_location(port);
         timed_getch();
      }
   }

   month++;
   if(month == 13) {
      month = 1;
      year++;
      ec += 10;
      ed += 1;
   }

	/* debt calculation original formula was:

			debt = debt + (debt * .1);

		int-based formula is the same, except it would never
		increase if debt is <= 10, so we fudge it with debt++
		in that case. Which means small debts accrue interest
		*much* faster, but that shouldn't affect gameplay much.
		There needs to be some overflow detection though... or
		maybe we let the overflow through, and the player can
		think of it as Wu forgiving the debt after enough years
		go by (or, he lost the paperwork?). Most likely though,
		the player gets his throat cut long before the amount
		overflows.

	*/

	if(debt) {
		if(debt > 10)
			debt += (debt / 10);
		else
			debt++;
	}
	if(debt >= DEBT_MAX) wu_assassin = 1;

#ifdef BIGNUM
	// no good, assumes a bignum can handle a fraction
	// big_mul(bank, bank, interest_rate);

	// bank = bank + (bank / 200);
	big_div(banktmp, bank, interest_denom);
	big_add(bank, bank, banktmp);
	if(big_cmp(bank, big0) != 0) bank_dirty = 1;
#else
	/* bank calculation original formula was:
			bank = bank + (bank * .005);
		int-based formula is the same, except when bank <= 200,
		it's linear.
	*/
	if(bank) {
		if(bank > 200)
			bank += (bank / 200);
		else
			bank++;
	}
	if(bank > 0) bank_dirty = 1;
#endif

   set_prices();

	clear_msg_window();
   // cputs("Arriving at ");
	print_msg(M_arriving_at);
   // cputs(location[port]);
	print_location(port);
   // cputs("...");
	print_msg(M_ellipsis);
   timed_getch();

   return;
}

void li_yuen_extortion(void) {
   int time = get_time();

	/*
   float i = 1.8,
         j = 0,
         amount = 0;
			*/
	unsigned long amount = 0;
	unsigned int i = 2, j = 0;

   if(time > 12) {
      j = randi() % (2 * (1000 * time));
      i = 1;
   }

   // amount = ((cash / i) * ((float) randi() / RAND_MAX)) + j;
	amount = randlmod((cash >> (i - 1))) + j;

	if(!amount) return; /* asking for 0 is dumb */

	compradores_report();
	// cprint_li_yuen();
	// cputs(" asks ");
	print_msg(M_asks);
	cprintfancy(amount);
	// cputs(" in donation\nto the temple of Tin Hau, the Sea\nGoddess. Will you pay? ");
	print_msg(M_in_donation);

   if(yngetc(0) == 'y') {
      if(amount <= cash) {
         cash -= amount;
			cash_dirty = 1;
         li = 1;
      } else {
			clear_msg_window();
         // cputs("you do not have enough cash!!\n\n");
			print_msg(M_not_enough_cash);

         timed_getch();

			cprint_Do_you_want();
			cprint_elder_brother_wu();
			// cputs("to make up\nthe difference for you? ");
			print_msg(M_make_up_difference);

         if(yngetc(0) == 'y') {
				clear_msg_window();
            amount -= cash;
            debt += amount;
            cash = 0;
				cash_dirty = 1;
            li = 1;

				cprint_elder_brother_wu();
				/*
				cputs("has given Li Yuen the\n"
						"difference between what he wanted and\n"
						"your cash on hand and added the same\n"
						"amount to your debt.\n");
						*/
				print_msg(M_given_the_diff);
         } else {
				clear_msg_window();
            cash = 0;
				cash_dirty = 1;
				// cputs("Very well. ");
				print_msg(M_very_well);
				cprint_elder_brother_wu();
				/*
				cputs("will not pay\n"
						"Li Yuen the difference.  I would be very\n"
						"wary of pirates if I were you.");
						*/
				print_msg(M_will_not_pay);
         }
			timed_getch();
      }
   }

   port_stats();
}

#ifdef BIGNUM
void you_only_have(unsigned char in_bank) {
	clear_msg_window();

	// cputs("you only have ");
	print_msg(M_you_only_have);
	if(in_bank)
		cprintfancy_big(bank);
	else
		cprintfancy(cash);
	// cputs("\nin ");
	print_msg(M_nl_in_spc);
	// cputs(in_bank ? "the bank" : "cash");
	print_msg(in_bank ? M_the_bank : M_cash);
	// cputs(".\n");
	good_joss_timed_getch();
}
#else
void you_only_have(unsigned char in_bank) {
	clear_msg_window();
	// gotox0y(18);
	// clrtobot();

	cprint_taipan_comma();
	cputs("you only have ");
	cprintfancy(in_bank ? bank : cash);
	cputs("\nin ");
	cputs(in_bank ? "the bank" : "cash");
	cputs(".\n");
	good_joss_timed_getch();
}
#endif

void elder_brother_wu(void) {
   int choice = 0;

   unsigned long wu = 0;

	compradores_report();
   // cputs("Do you have business with Elder Brother\nWu, the moneylender? ");
	print_msg(M_do_you_have_biz_with_wu);

   for (;;)
   {
      gotoxy(21, 19);

      // choice = agetc();
		choice = yngetc('n');
      if(choice != 'y')
         break;

		if((cash == 0) &&
#ifdef BIGNUM
				(big_cmp(bank, big0) == 0)
#else
				(bank == 0)
#endif
				&& (guns == 0) &&
				have_no_cargo())
		{
			int i = randi()%1500 + 500,
				 j;

			wu_bailout++;
			j = randi()%2000 * wu_bailout + 1500;

			for (;;)
			{
				compradores_report();
				/*
				cputs("Elder Brother is aware of your plight,\n"
						"Taipan. He is willing to loan you an\n"
						"additional ");
						*/
				print_msg(M_aware_of_your_plight);
				cprintuint(i);
				// cputs(" if you will pay back\n");
				print_msg(M_if_you_will_pay_back);
				cprintuint(j);
				// cputs(". Are you willing");
				print_msg(M_are_you_willing);
				cprint_taipan_prompt();

				choice = agetc();
				if(choice != 'y') {
					compradores_report();
					// cputs("Very well, Taipan, the game is over!\n");
					print_msg(M_game_is_over);
					under_attack_timed_getch();

					final_stats();
				} else {
					cash += i;
					cash_dirty = 1;
					debt += j;
					port_stats();

					compradores_report();
					// cputs("Very well, Taipan. Good joss!!\n");
					print_msg(M_very_well_good_joss);
					bad_joss_timed_getch();

					return;
				}
			}
		} else if ((cash > 0) && (debt != 0)) {
			for (;;)
			{
				compradores_report();
				how_much();
				do_you_wish();
				// cputs("to repay\nhim? ");
				print_msg(M_to_repay_him);

				wu = get_num();
				if(wu == UINT32_MAX)
					wu = cash;

				if(wu <= cash) {
					if(wu > debt) wu = debt;
					cash -= wu;
					cash_dirty = 1;
					debt -= wu;

					/*
					// currently debt is unsigned so the negative debt
					// bug (or feature) is unimplemented.
					if ((wu > debt) && (debt > 0))
						debt -= (wu + 1);
					else
						debt -= wu;
					 */

					break;
				} else {
					you_only_have(0);
				}
			}
		}
		port_stats();

		for (;;)
		{
			compradores_report();
			how_much();
			do_you_wish();
			// cputs("to \nborrow? ");
			print_msg(M_to_borrow);

			wu = get_num();

			// TODO: handle case where (cash * 2) would overflow!
			if(wu == UINT32_MAX)
			{
				wu = (cash * 2);
			}
			if((wu <= (cash * 2)) && !would_overflow(cash, wu))
			{
				cash += wu;
				cash_dirty = 1;
				debt += wu;
				break;
			} else {
				// cputs("\n\nHe won't loan you so much");
				print_msg(M_wont_loan);
				good_joss_timed_getch();
			}
		}
		port_stats();

		// break;

		/* do NOT let him steal the money back on the SAME TURN
			he loans it to you! */
		return;
   }

   if((debt > 20000) && (cash > 0) && (one_chance_in(5))) {
      unsigned char num = rand1to3();

      cash = 0;
		cash_dirty = 1;
      port_stats();

		compradores_report();
		cprint_bad_joss();
		cprintuchar(num);
		/*
		cputs(" of your bodyguards have been killed\n"
				"by cutthroats and you have been robbed\n"
				"of all of your cash");
				*/
		print_msg(M_bodyguards_killed);
		under_attack_timed_getch();
   }

   return;
}

void good_prices(void) {
	unsigned char i = randi()%4;

	compradores_report();
	// cprint_taipan();
   // cputs("!! The price of ");
	print_msg(M_the_price_of);
	// cputs(item[i]);
	print_item(i);
	// cputs("\n has ");
	print_msg(M_nl_has_spc);

	if(randi()&1) {
      price[i] *= (randi()%5 + 5);
      // cputs("risen");
		print_msg(M_risen);
	} else {
      price[i] /= 5;
		/* somehow general cargo dropped to 0 once. stop it. */
		if(price[i] < 1) price[i] = 1;
      // cputs("dropped");
		print_msg(M_dropped);
	}
	// cputs(" to ");
	print_msg(M_spc_to_spc);

	cprintulong(price[i]);
	// cputs("!!\n");
	print_msg(M_bang_bang_nl);
	good_joss_timed_getch();
}

int port_choices(void) {
   char choice;
	char retire_ok = 0;

	compradores_report();

   // cputs("present prices per unit here are"); /* NB: exactly 40 cols */
	print_msg(M_prices_here_are);

	// ===> free code space $0f7b (3936, 3.9K)
	// saves 46 bytes:
	for(choice = 0; choice < 4; ++choice) {
		gotox(3 + ((choice & 1) * 16));
		if(choice == 3)
			// cputs("General");
			print_msg(M_general_shortname);
		else
			// cputs(item[choice]);
			print_item(choice);
		// cputc(':');
		cprint_colon_space();
		gotox(11 + ((choice & 1) * 18));
		cprintulong(price[choice]);
		if(choice == 1) crlf();
	}

	/*
	// original version:
	// ===> free code space $0f32 (3890, 3.8K)
   cputs("   Opium:          Silk:\n");
   cputs("   Arms:           General:\n");
   gotoxy(11, 19);
	cprintulong(price[0]);
   gotoxy(29, 19);
	cprintulong(price[1]);
   gotoxy(11, 20);
	cprintulong(price[2]);
   gotoxy(29, 20);
	cprintulong(price[3]);
	*/

	gotox0y22();
	clrtobot();

#ifdef BIGNUM
	if(port == 1) {
		/*
			// this speeds things up ever so slightly when cash is
			// low, but costs 68 bytes of code. Leave out for now.
		if(cash > 1000000L) {
			retire_ok = 1;
		} else if(big_cmp(bank, big1M) >= 0) {
			retire_ok = 1;
		} else {
		*/
			bignum(tmp);
			ulong_to_big(cash, tmp);
			big_add(tmp, tmp, bank);
			retire_ok = (big_cmp(tmp, big1M) >= 0);

			// if(big_cmp(tmp, big1M) >= 0)
				// retire_ok = 1;

			/*
		}
		*/
	}
#else
	retire_ok = (port == 1 && ((cash + bank) >= 1000000L));
#endif

	// cputs("Shall I Buy, Sell, ");
	print_msg(M_shall_i_buy_sell);

	if(port == 1)
		// cputs("Visit bank, Transfer\ncargo, ");
		print_msg(M_bank_transfer);

	if(!retire_ok) cputs("or ");

	cputs("Quit trading");

	// if(retire_ok) cputs(", or Retire");
	if(retire_ok) print_msg(M_or_retire);
	cprint_question_space();

	for(;;) {
		choice = lcgetc();
		if(choice == 'b' || choice == 's' || choice == 'q')
			break;
		if(port == 1) {
			if(retire_ok && choice == 'r')
				break;
			if(choice == 't' || choice == 'v')
				break;
		}
	}

   return choice;
}


/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/
char what_do_you_wish_me_to(char *buy_or_sell) {
	gotox0y22();
	clrtobot();
	// cputs("What ");
	print_msg(M_what);
	do_you_wish();
	// cputs("me to ");
	print_msg(M_me_to);
	cputs(buy_or_sell);
	cprint_taipan_prompt();
	return get_item_port();
}
/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/

void buy(void) {
   int choice;
   unsigned long afford, amount;

	choice = what_do_you_wish_me_to("buy");
	if(choice == 5) return;

   for (;;) {
      gotoxy(31, 21);
      clrtobot();

      afford = cash / price[choice];
		rvs_on();
      // cputs(" You can ");
		print_msg(M_spc_you_can_spc);
		rvs_off();
      gotox0y22();
		how_much();
      // cputs(item[choice]);
		print_item(choice);
      // cputs(" shall");
		print_msg(M_spc_shall);
      gotoxy(31, 22);
		rvs_on();
      // cputs("  afford ");
		print_msg(M_spc_afford);
      gotoxy(31, 23);
		// cspaces(9);
      // gotoxy(31, 23);
		cblank(9);

		if(afford <       100) cspace();
		if(afford <     10000) cspace();
		if(afford <   1000000) cspace();
		if(afford < 100000000) cspace();

		cprintulong(afford);
		rvs_off();

      gotox0y(23);
      // cputs("I buy, ");
		print_msg(M_i_buy);
		cprint_taipan_colon();

      amount = get_num();
      if(amount == UINT32_MAX) {
         amount = afford;
      }
      if(amount <= afford) {
         break;
      }
   }

   cash -= (amount * price[choice]);
	cash_dirty = 1;
   hold_[choice] += amount;
   hold -= amount;

   return;
}

void sell(void) {
   int choice;
   unsigned long amount;

	choice = what_do_you_wish_me_to("sell");
	if(choice == 5) return;

   for (;;) {
      gotox0y22();
      clrtobot();

		how_much();
      // cputs(item[choice]);
		print_item(choice);
      // cputs(" shall\nI sell, ");
		print_msg(M_shall_i_sell);
		cprint_taipan_colon();

      amount = get_num();

      if (amount == UINT32_MAX) {
         amount = hold_[choice];
      }

		if(would_overflow(cash, amount * price[choice])) {
			too_much_cash();
			continue;
		}

      if (hold_[choice] >= amount) {
         hold_[choice] -= amount;
         break;
      }
   }

   cash += (amount * price[choice]);
	cash_dirty = 1;
   hold += amount;

   return;
}

/*
#ifdef CART_TARGET
# pragma code-name (push, "HIGHCODE")
#endif
*/
char would_overflow(unsigned long a, unsigned long b) {
	return ((UINT32_MAX - b) <= a);
}

void too_much_cash(void) {
	clear_msg_window();
	// cputs("\nYou cannot carry so much cash");
	print_msg(M_too_much_cash);
	// cputs("\nYour ship would sink under the weight\nof your riches.\n");
	print_msg(M_ship_would_sink);
	bad_joss_timed_getch();
}
/*
#ifdef CART_TARGET
# pragma code-name (pop)
#endif
*/


void visit_bank(void) {
   unsigned long amount = 0;
#ifdef BIGNUM
	bignum(bigamt);
	bignum(biglimit);
	bignum(bigcash);
#endif

   for (;;)
   {
		compradores_report();
		how_much_will_you();
      // cputs("deposit? ");
		print_msg(M_deposit);

      amount = get_num();
      if (amount == UINT32_MAX)
      {
         amount = cash;
      }
      if (amount <= cash)
      {
         cash -= amount;
#ifdef BIGNUM
			ulong_to_big(amount, bigamt);
			big_add(bank, bank, bigamt);
#else
         bank += amount;
#endif
			if(amount) bank_dirty = cash_dirty = 1;
         break;
      } else {
			you_only_have(0);
      }
   }
   port_stats();

   for (;;)
   {
		compradores_report();
		how_much_will_you();
      // cputs("withdraw? ");
		print_msg(M_withdraw);

      amount = get_num();
#ifdef BIGNUM
		if(amount == UINT32_MAX) {
			big_copy(bigamt, bank);
		} else {
			ulong_to_big(amount, bigamt);
		}

		ulong_to_big(cash, bigcash);
		big_sub(biglimit, big_max_ulong, bigcash);

		if(big_cmp(bigamt, biglimit) >= 0) {
			too_much_cash();
			continue;
		}

		if(big_cmp(bank, bigamt) < 0) {
			you_only_have(1);
		} else {
			big_sub(bank, bank, bigamt);
			big_add(bigcash, bigcash, bigamt);
			big_to_ulong(bigcash, &cash);
			if(amount) bank_dirty = cash_dirty = 1;
			break;
		}
#else
      if (amount == UINT32_MAX)
      {
         amount = bank;
      }
      if (amount <= bank)
      {
         cash += amount;
         bank -= amount;
			if(amount) bank_dirty = cash_dirty = 1;
         break;
      } else {
			you_only_have(1);
      }
#endif
   }
   // port_stats(); /* don't do this here, the caller does it after we return */

   return;
}

#ifdef BIGNUM_TEST
void bignum_test(void) {
	int i;
	bignum(n);
	bignum(o);

	ulong_to_big(1L, n);
	ulong_to_big(11L, o);

	for(i = 0; i < 14; i++) {
		cprintfancy_big(n);
		cspace();
		big_negate(n);
		cprintfancy_big(n);
		crlf();
		big_mul(n, n, o);
	}
	agetc();
	ulong_to_big(1100000L, n);
	cprintfancy_big(n);
	ulong_to_big(1010000L, n);
	cprintfancy_big(n);
	ulong_to_big(1001000L, n);
	cprintfancy_big(n);

hangx: goto hangx;
}
#endif

#ifdef FINAL_STATS_TEST
void final_stats_test(void) {
	cputs("cash? ");
	cash = get_num();
	crlf();
	cputs("debt? ");
	debt = get_num();
	crlf();
	cputs("year? ");
	year = get_num();
	month = 1;
	final_stats();
}
#endif

/* N.B. cc65 is perfectly OK with main(void), and it avoids
   warnings about argv/argc unused. */
int main(void) {
   char choice;

	/* newtitle.s saves the OS's display list pointer in FRE,
		sets up its own DL, and uses narrow playfield mode. First
		thing we do it put things back the way they were.
		FONT_ADDR is set on the command line (see the Makefile). */
	POKE(560, PEEK(0xda)); // restore the
	POKE(561, PEEK(0xdb)); // display list
	POKE(756, FONT_ADDR / 256); // use our custom font
	POKE(731, 1);    // disable keyclick on XL/XE (does nothing on 400/800)
	POKE(559, 34);        // turn on the screen (normal playfield)

#ifdef FINAL_STATS_TEST
	while(1) final_stats_test();
#endif

#ifdef LORCHA_TEST
	gotox0y(0);
	clrtoeol();
	for(choice = 0; choice < 10; choice++) {
		draw_lorcha(choice);
	}
	while(1) {
		choice = agetc() % 10;
		damage_lorcha(choice);
	}
#endif

#ifdef MCHENRY_TEST
	{
		while(1) {
			clr_screen();
			cputs("year? ");
			year = get_num();
			crlf();
			cputs("dmg? ");
			damage = get_num();
			// cputs("\n");
			crlf();
			cputs("cap? ");
			capacity = get_num();
			mchenry();
		}
	}
#endif


#ifdef BIGNUM_TEST
	bignum_test();
#endif

	init_game();

   for (;;) {
      port_stats();

		if(wu_assassin) {
			wu_assassin = 0;
			compradores_report();
			// cputs("you have been assassinated!");
			print_msg(M_assassinated_1);
			under_attack_timed_getch();
			compradores_report();
			// cputs("As the masked figure plunges the blade\n"
					// "into your heart, he says:\n");
			print_msg(M_assassinated_2);
			timed_getch();
			compradores_report();
			cprint_elder_brother_wu();
			// cputs("regrets to inform you\n"
					// "that your account has been terminated\n"
					// "with extreme prejudice.");
			print_msg(M_assassinated_3);
			timed_getch();
			final_stats();
		}

		if(port == 1) {
			if((li == 0) && (cash > 0))
				li_yuen_extortion();

			if(damage > 0)
				mchenry();

			if((debt >= 10000) && (wu_warn == 0)) {
				int braves = randi()%100 + 50;

				compradores_report();
				cprint_elder_brother_wu();
				// cputs("has sent ");
				print_msg(M_has_sent);
				cprintuint(braves);
				// cputs(" braves\nto escort you to the Wu mansion");
				print_msg(M_braves_to_escort);

				timed_getch();

				clear_msg_window();
				cprint_elder_brother_wu();
				/*
				cputs("reminds you of the\n"
						"Confucian ideal of personal worthiness,\n"
						"and how this applies to paying one's\ndebts.\n");
						*/
				print_msg(M_wu_warn_1);

				timed_getch();

				clear_msg_window();
				/*
				cputs("He is reminded of a fabled barbarian\n"
						"who came to a bad end, after not caring\n"
						"for his obligations.\n\n"
						"He hopes no such fate awaits you, his\nfriend");
						*/
				print_msg(M_wu_warn_2);

				timed_getch();

				wu_warn = 1;
			}

			elder_brother_wu();
		}

		if(one_chance_in(4)) {
			if(one_chance_in(2))
				new_ship();
			else
				new_gun();
		}

      if((port != 1) && (one_chance_in(18)) && (hold_[0] > 0)) {
         // float fine = ((cash / 1.8) * ((float) randi() / RAND_MAX)) + 1;
			// the 1.8 is now a 2
			unsigned long fine = 0;
			if(cash > 0)
				fine = randlmod(cash >> 1) + 1;

         hold += hold_[0];
         hold_[0] = 0;
         cash -= fine;
			cash_dirty = 1;

         port_stats();

			/* Note: "fined you 0" if you have no cash looks weird, but is NOT
				a bug, the original Apple II code does that. */
			compradores_report();
			cprint_bad_joss();
         // cputs("The local authorities have seized your\n"
					// "Opium cargo and have also fined you\n");
			print_msg(M_siezed_opium);
			cprintfancy(fine);
			cprint_taipan_bang();
			crlf();

         under_attack_timed_getch();
      }

		/*
      if ((one_chance_in(50)) &&
          ((hkw_[0] + hkw_[1] + hkw_[2] + hkw_[3]) > 0))
			 */
      if(one_chance_in(50) && !hkw_is_empty()) {
         int i;

         for (i = 0; i < 4; i++)
         {
            // hkw_[i] = ((hkw_[i] / 1.8) * ((float) randi() / RAND_MAX));
				// the 1.8 is now a 2
            hkw_[i] = randlmod(hkw_[i] >> 1);
         }

         port_stats();

			compradores_report();
         // cputs("Messenger reports large theft\nfrom warehouse");
			print_msg(M_whouse_theft);

         timed_getch();
      }

      if(one_chance_in(20)) {
         if (li > 0) li++;
         if (li == 4) li = 0;
      }

      if((port != 1) && (li == 0) && (!one_chance_in(4))) {
			compradores_report();
			// cprint_li_yuen();
			/*
         cputs(" has sent a Lieutenant,\n"
					"Taipan.  He says his admiral wishes\n"
					"to see you in Hong Kong, posthaste!\n");
					*/
			print_msg(M_has_sent_lieutenant);
			bad_joss_timed_getch();
      }

      if(one_chance_in(9))
         good_prices();

      if((cash > 25000) && (one_chance_in(20))) {
         // float robbed = ((cash / 1.4) * ((float) randi() / RAND_MAX));
			// line below changes the 1.4 to 1.5
			unsigned long robbed = randlmod((cash >> 2) + (cash >> 1));

         cash -= robbed;
			cash_dirty = 1;
         port_stats();

			compradores_report();
			cprint_bad_joss();
         // cputs("You've been beaten up and\nrobbed of ");
			print_msg(M_beaten_robbed);
			cprintfancy(robbed);
         // cputs(" in cash");
			print_msg(M_in_cash);
			under_attack_timed_getch();
      }

		for(;;) {
			static unsigned char new_port;
			new_port = 0;
			while(!new_port) {
				switch (choice = port_choices()) {
					case 'b':
						buy();
						break;

					case 's':
						sell();
						break;

					case 'v':
						visit_bank();
						break;

					case 't':
						transfer();
						break;

					case 'q':
						if(hold < 0)
							overload();
						else
							new_port = choose_port();
						break;

					case 'r':
						retire();
				}

				port_stats();
			}

			port = new_port;
			quit();
			break;
		}
   }

	return 0;
}
