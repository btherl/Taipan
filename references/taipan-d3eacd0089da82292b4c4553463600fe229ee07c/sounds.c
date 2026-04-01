/* this file is no longer used. the sound code was rewritten in asm,
   and lives in soundasm.s. This file is kept purely for reference. */

/* Sounds for Taipan! Atari 800 port.

	Made by capturing the Apple II audio and taking wild guesses,
	then refining them.

	I'm not shooting for Atari sounds that are identical to the
	Apple ones: (a) it's impossible anyway, and (b) the Apple
	sounds are a bit harsh to the ear. Hopefully these sound
	a little smoother while still being pretty close.
*/

#include <atari.h>
#include <peekpoke.h>
#include "sounds.h"

/* location we will look at, to see if sound is disabled.
	0 = enabled, 1 = disabled. If you change this here,
	change it in newtitle.s also! */
static int sound_disabled = 0x06ff;

/* to build standalone xex that just plays the 3 sounds:
	cl65 -DTESTXEX -t atari -o sounds.xex sounds.c 
*/
#ifdef TESTXEX
#include <stdio.h>

void jsleep(unsigned int j) {
	POKE(20,0);
	while(PEEK(20) < j)
		;
}
#else
extern void __fastcall__ jsleep(unsigned int j);
#endif

/* set volume 10, distortion 10 on audio channel 0 */
void init_sound(unsigned char audc1) {
	if(PEEK(sound_disabled)) return;

	/* init POKEY audio */
	POKEY_WRITE.audctl = 0;
	POKEY_WRITE.skctl = 3;
	POKEY_WRITE.audc1 = audc1; /* SOUND 0,x,audc1>>4,audc1&0x0f */
}

/* silence audio channel 0 */
void stop_sound(void) {
	POKEY_WRITE.audc1 = 0x00; /* SOUND 0,x,0,0 */
}

void bad_joss_sound(void) {
	unsigned char i;

	init_sound(0xaa);
	for(i=0; i<10; i++) {
		POKEY_WRITE.audf1 = 80-i*8;
		jsleep(1);
	}
	stop_sound();
}

void good_joss_sound(void) {
	unsigned char i, j;

	init_sound(0xaa);
	for(j=0; j<3; j++) {
		for(i=0; i<4; i++) {
			POKEY_WRITE.audf1 = 20-i*5;
			jsleep(2);
		}
	}
	stop_sound();
}

void under_attack_sound(void) {
	unsigned char i, j;

	init_sound(0xaa);
	for(j=0; j<3; j++) {
		for(i=0; i<3; i++) {
			POKEY_WRITE.audf1 = 20-i*3;
			jsleep(3);
		}
	}
	stop_sound();
}

#ifdef NEW_SOUNDS
void cannon_sound(void) {
	unsigned char i;

	init_sound(0xaa);
	for(i = 20; i < 40; i += 1) {
		POKEY_WRITE.audf1 = i;
		jsleep(1);
	}

	init_sound(0x8a);
	POKEY_WRITE.audf1 = 120;
	for(i = 15; i > 3; i--) {
		POKEY_WRITE.audc1 = 0x80 | i;
		jsleep(3);
	}

	stop_sound();
}

/* this isn't a very good explosion yet */
void weve_been_hit_sound(void) {
	unsigned char i;

	init_sound(0x8a);
	POKEY_WRITE.audf1 = 200;
	for(i = 15; i > 3; i--) {
		POKEY_WRITE.audc1 = 0x80 | i;
		POKEY_WRITE.audf1 = 200-i*2;
		jsleep(4);
	}

	stop_sound();
}
#endif

#ifdef TESTXEX
int main(void) {
	for(;;) {
		puts("Bad joss, Taipan!");
		bad_joss_sound();
		jsleep(30);

		puts("Good joss, Taipan!");
		good_joss_sound();
		jsleep(30);

		puts("1.0E+97 hostile ships approaching, Taipan!");
		under_attack_sound();
		jsleep(30);

#ifdef NEW_SOUNDS
		puts("We're firing on them!");
		cannon_sound();
		jsleep(30);

		puts("We've been hit!");
		weve_been_hit_sound();
		jsleep(30);
#endif
	}

hang: goto hang;
	return 0;
}
#endif
