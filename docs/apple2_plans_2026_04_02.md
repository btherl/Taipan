### Plans for the Apple 2 version.

## General notes

In the majority of scenes, the screen is divided into two parts.  The top 16 lines are the status screen, and the bottom 8 lines are used for prompts and notifications.

Exceptions are during battle, and the screens shown after winning or losing the game.

While at port, the top line of the bottom 8 typically shows "Comprador's Report".

While at sea, the top line of the bottom 8 typically shows "  Captain's Report" (two leading spaces).

## Upon arrival at HK, display the following in the lower 8 lines of the screen, between the "-----" markers.

-----
Comprador's Report

Do you have business with Elder Brother
Wu, the moneylender?
-----

Accept a single character response Y or N.

If N, continue to main port screen

If Y:

-----
Comprador's Report

How much do you wish to
borrow?
-----

This is a numeric input, limited to 9 digits.  Left arrow deletes the last digit.  Backspace does not work.  So, this is a different input to the one used for Firm name.

The amount entered will be borrowed, subject to existing borrowing rules.

If any amount is outstanding from a *previous* borrowing (not from borrowing just now), then Wu will ask about repayment:

-----
Comprador's Report

How much do you wish to
repay?
-----

Again, numeric input.  The amount entered will be repaid.

## HK Port dialog

-----
Comprador's Report

Taipan, present prices per unit here are
   Spices: 16500  Silk: 110
   Arms: 180      General: 10

Shall I Buy, Sell, Visit bank, Transfer
cargo, or Quit trading?
-----

Valid responses are B, S, V, T, Q.

## Buying goods

If "B" entered, line 7+8 are erased and replaced with "What do you wish me to buy, Taipan?" on one line.
Valid responses are P, S, A, G.  After selection:
"How much General Cargo shall
I buy, Taipan?"

On lines 6-8 on the right, from columns 31-39, inverted text displays:
" You can "
"  afford "
"    0    "

A valid entry will perform the transaction.  An invalid entry, including exceeding available cash (but not available hold space, we are allowed to overload) will clear input and remain in the dialog, waiting for a valid entry.

## Selling goods

If "S" entered, line 7+8 are erased and replaced with "What do you wish me to sell, Taipan?" on one line.
Valid responses are P, S, A, G.  After selection:
"How much General Cargo shall
I sell, Taipan?"

A valid entry will perform the transaction.  An invalid entry, including exceeding actual cargo available, will clear input and remain in the dialog, waiting for a valid entry.

## Visit bank

"V" will enter the bank dialog

Lines 3-8 are cleared, line 3 displays "How much will you deposit?".  This accepts up to 9 digits.

If more money is entered than is available, lines 5-6 display:
"Taipan, you only have 0
in cash"
This message clears if a key is pressed, or after 5 seconds.

After deposits are handled, line 3 displays: "How much will you withdraw?".  This acceptes up to 9 digits.

If more money is entered than available in the bank, lines 5-6 display:
"Taipan, you only have 0
in the bank."
This message clears if a key is pressed, or after 5 seconds.

Once both deposits and withdrawals are handled, control returns to the main dock screen, displaying goods prices.

## Transfer cargo

If "T" is entered, but you have no cargo, lines 6-8 are cleared, and line 6 displays "You have no cargo, Taipan.".  This message clears on keypress, or after 5 seconds.

If cargo is available, each good is asked about in turn.  Dialog follows.

Each question is only asked if there is at least 1 of that item available to move in that direction.

The cursor appears one space after the question mark, and allows up to 9 digits.  Left arrow deletes a digit, backspace does not do anything.

If you enter more than is available, the line "You only have 50, Taipan." appears 2 lines below the cursor line (one blank line between), with a 5 second delay, then the same question is asked again.  The same thing happens whether moving to warehouse or from warehouse.

-----
Comprador's Report

How much Silk shall I move
to the warehouse, Taipan?
-----

-----
Comprador's Report

How much Silk shall I move
aboard ship, Taipan?
-----

## Quit trading

If "Q" is entered, lines 3-8 are cleared and this displays:

-----
Taipan, do you wish to go to:
1) Hong Kong, 2) Shanghai, 3) Nagasaki,
4) Saigon, 5) Manila, 6) Singapore, or
7) Batavia ? 
-----

There is a single space after the "?", before the input, allowing numbers 1-7.

After a port is selected, lines 3-8 are cleared, and the text "Arriving at Saigon" (or other port) appear.  Text remains displayed for 3 seconds.

## Ports other than Hong Kong

After arriving at a port other than Hong Kong, the following displays:

-----
Comprador's Report

Taipan, present prices per unit here are
   Spices: 16500  Silk: 110
   Arms: 180      General: 10

Shall I Buy, Sell, or Quit trading?
-----

All available options work as they do in Hong Kong.

## Li Yuen request

If not under Li Yuen's protection, then after arriving at a port, the following message displays for 5 seconds:

-----
Comprador's Report

Li Yuen has send a lieutenant,
Taipan.  He says his admiral wishes
to see you in Hong Kong, posthaste!
-----

## Price drop

If a price drop triggers, this displays after "Arriving at port" has cleared.  The format is:

-----
Comprador's Report

Taipan!!  The price of Arms
has dropped to 36!!
-----

This displays for 5 seconds or until a key is pressed.

This can also show "risen" instead of "dropped"

## Battle notification

-----
  Captain's Report

2 hostile ships approaching, Taipan!!
-----

## Battle screen

-----
   2 ships attacking, Taipan!  | We have
Your orders are to:            |  5 guns
                               +--------
Current seaworthiness: Perfect (100%)
-----

Below this the ships will display.  For now, we will continue using the text "#" ships, until we get proper sprites and layout.

## Fight

If "F" is pressed, the text "Fight" displays after "Your orders are to: "

And below, on line 4, the text "Aye, we'll fight 'em, Taipan!" shows

## Fight

If "F" is pressed, the text "Fight" displays after "Your orders are to: "

And below, on line 4, the text "Aye, we'll fight 'em, Taipan!" shows.

After 2 seconds, line 4 changes to "We're firing on 'em, Taipan!"

If enemy ships are sunk, line 4: "Sunk 2 of the buggers, Taipan!"

If all ships sunk, line 4: "We got 'em all, Taipan!!"

## After winning battle

Status screen draws again.  Lines 2-3 at the bottom show:

"We've captured some booty
It's worth 2486!"

This shows for 5 seconds, followed by "Arriving at (port)"

## Li Yuen demands tribute

If Li Yuen has not been paid, and player has non-zero cash, and arrive in HK, this message appears:

Li Yuen asks 81 in donation
to the temple of Tin Hau, the Sea
Goddess.  Will you pay?

Valid answers are Y or N

This is followed by "Do you have business with Elder Brother
Wu, the moneylender? "

## Li Yuen battle

-----
  Captain's Report

Li Yuen's pirates, Taipan!!
-----

if under protection, after 5 second delay or keypress:

-----
  Captain's Report

Li Yuen's pirates, Taipan!!

Good joss!! They let us be!!
-----


## Storm

-----
  Captain's Report

Storm, Taipan!!
-----

5 second delay, or until keypress, then

-----
  Captain's Report

Storm, Taipan!!

    We made it!!
-----

If blown off course:

-----
  Captain's Report

We've been blown off course
to Batavia
-----

## Ship trade-in

-----
Comprador's Report

Do you wish to trade in your fine
ship for one with 50 more capacity by
paying an additional 2281, Taipan?
-----

"fine" can be replaced, depending on ship status.


## Retirement

If net value is over 1 million, the Hong Kong menu on lines 7-8 changes to:

Shall I Buy, Sell, Visit bank, Transfer
cargo, Quit trading, or Retire?

If "R" is chosen, lines 3-8 of the bottom section show the following inverted text
in a 25 wide inverted box (made of spaces and text, no box border).

-----

 Y o u ' r e    a

 M I L L I O N A I R E !

-----

Then the final status screen shows:

-----
Your final status:

Net Cash: 1.52 Million

Ship size: 210 units with 7 guns

You traded for 2 years and 2 months

Your score is 421.



Your Rating:
+-------------------------------+
|Ma Tsu         50,000 and over |
|Master Taipan   8,000 to 49,999|
|Taipan          1,000 to  7,999|
|Compradore        500 to    999|
|Galley Hand       less than 500|
+-------------------------------+

Play again?
-----

The "Your score is 421" line is inverted
The rating you achieved (in the box listing 5 rating levels) is also inverted.

Valid responses here are "Y" or "N".  "N" returns to the main menu.  "Y" returns to the screen for selecting Firm Name.

## Shipyard repaird

Upon arrival in Hong Kong with a damaged ship:

-----
Comprador's Report

Taipan, Mc Henry from the Hong Kong
Shipyards has arrived!  He says, 'I see
ye've a wee bit of damage to yer ship.
Will ye be wanting reparis?' _
-----

This dialog accepts Y or N at the cursor.

If "N", continue to next dialog.

If "Y":

-----
Comprador's Report

Och, 'tis a pity to be 2% damaged.

We can fix yer whole ship for 204,
or make partial repairs if you wish.
How much will ye spend? _
-----

If amount higher than cash on hand is entered, then following message on 5 second delay:

-----
Comprador's Report

Taipan, you do not have enough cash!!
-----

If an amount entered (including 0), do any repairs, then continue to next dialog.


## Buy a gun

-----
Comprador's Report

Do you wish to buy a ship's gun
for 784, Taipan? _
-----

This is a Y / N dialog, using cursor input at the marked "_"

## Ship upgrade

-----
Comprador's Report

Do you wish to trade in your damaged
ship for one with 50 more capacity by
paying an additional 3908, Taipan? _
-----

The word "damaged" is underlined, we may need to implement support for this somehow.
Answer is "Y" or "N" as a cursor input, at the marked "_"

If ship is in perfect condition, it will say "fine" instead of "damaged", and not be underlined.


## Ordering of port arrival dialogs

Note that the "ship upgrade" dialog appears before "buy a gun" dialog.

Li Yuen donation request comes before Mc Henry ship repairs

Wu is after ship repairs

Ships Gun is after Wu

Li Yuen admiral warning (at non-HK ports) comes after gun and ship upgrade dialogs.
