# Fixes to Taipan combat system

## Fighting without guns

If instructed to fight, but we have no guns, this message should display:

We have no guns, Taipan!!

followed by the enemy ships firing, and the combat loop continuing as per usual

## End of battle

If the ship is sunk, the lines 1-16 status screen is drawn first, followed by:

The buggers got us, Taipan!!
It's all over, now!!!

Then continuing to the score screen

----

If we won the battle, the order of events are:

Line 4: We got 'em all, Taipan!!
Draw lines 1-16 status screen
Line 17 blank (no "report" line)
Line 19: We've captured some booty
Line 20: It's worth 1389!
(3 second delay)
Then standard arrival dialogue:
=====
  Captain's Report

Arriving at Manila
=====

## No action selected

If no action is selected after a few seconds, this message displays:

Taipan, what shall we do??

## Battle messages

Aye, we'll fight 'em, Taipan!
We're firing on 'em, Taipan!
(firing animations, damage to ships, ships sinking)
Sunk 2 of the buggers, Taipan!
(ships removed from screen, if running ships are visible)
2 ran away, Taipan!
They're firing on us, Taipan!
(screen glitch, switching rapidly to garbage page and back)
We've been hit, Taipan!
The buggers hit a gun, Taipan!!
Current seaworthiness:  Prime (90%)
(blank)
Aye, we'll fight 'em, Taipan!

## Throw Cargo

When selected, the display becomes like this:

Lines 1-4:
=====
   2 ships attacking, Taipan!
Your order are to: Throw cargo

What shall I throw overboard, Taipan? _
=====

Lines 7-17 (ship lines)
Lines 19-21:
=====
You have the following on board, Taipan:
    Opium: 0            Silk: 0
     Arms: 0         General: 0
=====

After selection a cargo type and hitting enter, line 4 displays:
How much, Taipan? _
If no cargo is available, line 4 changes to:
There's nothing there, Taipan!

Then it continues to "They're firing on us, Taipan!" on line 4
