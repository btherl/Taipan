/* played when something bad happens */
void bad_joss_sound(void);

/* played when something good happens */
void good_joss_sound(void);

/* played before & during combat */
void under_attack_sound(void);

#ifdef NEW_SOUNDS
/* UNUSED: will be played when firing at an enemy ship */
void cannon_sound(void);

/* UNUSED: will be played while screen flashes in combat */
void weve_been_hit_sound(void);
#endif

/* rest of this file is a list of all the instances of each sound,
	gathered by playing the Apple II version in an emulator, and by
	reading the Applesoft source (the goggles, they do nothing!). It
	may be incomplete.

bad_joss_sound: CALL 2521
li yuen has sent a lieutenant... *
li yuen's pirates! (attacking) *
killed a bad guy (?) *
sunk X of 'em *
X ran away *
storm taipan! *
we made it! (after a storm) *
wu_bailout (very well, good joss) *
trying to enter an empty firm name
we got 'em all! *
let's hope we lose 'em! *
X ran away *
sunk X of the buggers *
they let us be *

good_joss_sound: CALL 2518
captured some booty *
we made it! (after combat) *
got away in combat *
you're already here! *
price has risen (dropped) *
there's nothing there (throwing cargo) *
ship overloaded *
you have only (trying to put too much in warehouse) *
you have only X in cash (paying Wu back, depositing in bank) *
you have only X in the bank *
warehouse will only hold an additional *
warehouse is full *
won't loan you so much *
you have no cargo (trying to put in warehouse) *

under_attack_sound: CALL 2512
X hostile ships approaching *
hit in combat *
beaten & robbed *
bodyguards killed *
very well, the game is over (wu_bailout) *
buggers hit a gun *
we've been hit *
what shall we do? *
we're going down (storm) *
X ships of li yuen's pirate fleet *
X hostile ships approaching *

*/
