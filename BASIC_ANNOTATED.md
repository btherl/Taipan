# Taipan! -- Fully Annotated BASIC Source Code

This document provides a complete, line-by-line annotation of the Taipan! AppleSoft BASIC source code (from `BASIC.txt`). It is intended as the primary reference for developers implementing the Roblox version of the game.

## AppleSoft BASIC Conventions

Before diving into the code, understand these conventions used throughout:

- **`FN R(N)`** -- User-defined function returning a random integer from 0 to N-1. Defined as `INT(USR(0) * X)` where `USR(0)` returns a random float 0-1. When used in `IF FN R(N) THEN ...`, the condition is TRUE (triggers) when the result is non-zero (values 1 through N-1), and FALSE when the result is 0. So `IF FN R(N)` fires (N-1)/N of the time. Conversely, `IF NOT FN R(N)` fires 1/N of the time.
- **`INT(x)`** -- Floor function. Truncates toward negative infinity.
- **`INT(x + 0.5)`** -- Rounds to nearest integer.
- **`GOSUB n / RETURN`** -- Subroutine call to line n; RETURN jumps back to the line after the GOSUB.
- **`GOTO n`** -- Unconditional jump to line n.
- **`ON x GOTO a,b,c`** -- Computed jump: goes to line a if x=1, b if x=2, c if x=3.
- **`USR(n)`** -- Calls machine-language routine number n. These handle display rendering, input processing, and sound effects. They are black boxes -- treat them as named functions with specific purposes noted in context.
- **`X = USR(n)`** -- The `X =` is required syntax for calling USR; the return value is typically discarded.
- **`CH$` / `CH%`** -- `CH$` is set to a string of valid input characters before calling the character input routine (GOSUB 100). After return, `CH%` holds the 1-based index of the character the player chose within that string.
- **`R1%`** -- Flag set to 1 when the player typed "A" (All) during a numeric input (GOSUB 150). Used throughout for "buy all", "sell all", "deposit all", etc.
- **`W`, `WW`, `I`, `J`, `K`** -- Frequently reused as temporary/scratch variables. Their meaning changes per context and is documented in each section.
- **`ST(K,J)`** -- Cargo storage array. K=1 means warehouse (Hong Kong godown), K=2 means ship hold. J=1..4 is the commodity index (1=Opium, 2=Silk, 3=Arms, 4=General Cargo).
- **`BP%(port, good)`** -- Base price matrix. Both indices are 1-based.
- **`PEEK(-16384)`** -- Reads the Apple II keyboard buffer. Values >= 128 mean a key is pressed.
- **`POKE -16368,0`** -- Clears the keyboard strobe (acknowledges the keypress).
- **`VTAB n` / `HTAB n`** -- Position cursor at vertical line n / horizontal column n.
- **`POKE 32..35`** -- Sets the text window boundaries (left margin, width, top, bottom).
- **`CALL address`** -- Calls a machine-language routine at a specific memory address. Used for sound effects and custom input routines.
- **`CHR$(n)`** -- Returns the character with ASCII code n. Used here for custom display control codes.
- **`&`** -- Ampersand command; in this program it draws horizontal lines of repeated characters for the UI border graphics.
- **`SGN(x)`** -- Returns -1 if x<0, 0 if x=0, 1 if x>0.

---

## SECTION 1: Initialization and Variable Setup (Line 10)

### Purpose
Line 10 is the very first executed line. It initializes key global variables to zero/default values, sets timing constants, and immediately jumps to the full game initialization at line 10000.

### Variables Initialized
| Variable | Value | Meaning |
|----------|-------|---------|
| `WK$` | `"*"` | String input buffer (initialized to non-empty) |
| `CH$` | `"*"` | Valid character input set (initialized to non-empty) |
| `CH%` | 0 | Character choice index |
| `WU%` | 0 | Wu prompt flag (modifies input behavior) |
| `R1%` | 0 | "All" input flag |
| `I, J, K` | 0 | Loop/scratch variables |
| `II, IJ, IK` | 0 | Inner loop/scratch variables |
| `T` | 300 | Base delay loop count for animations/pauses |
| `LT` | LOG(10) | Precomputed natural log of 10, used in big number formatting |
| `T$` | `"Taipan"` | Player title string, used in all messages addressing the player |

### Annotated Code

```basic
 10  CLEAR :WK$ = "*":CH$ = "*":CH% = 0:WU% = 0:R1% = 0:I = 0
     :J = 0:K = 0:II = 0:IJ = 0:IK = 0:T = 300:LT = LOG(10)
     :T$ = "Taipan": GOTO 10000
```
- `CLEAR` -- Clears all variables and strings to defaults.
- `WK$ = "*"` / `CH$ = "*"` -- Seed string variables so they are not empty (empty strings can cause issues in AppleSoft).
- `CH% = 0:WU% = 0:R1% = 0` -- Zero out input-related flags.
- `I = 0:J = 0:K = 0:II = 0:IJ = 0:IK = 0` -- Zero out all loop/scratch variables.
- `T = 300` -- **Animation timing constant.** Controls how long delay loops run. Higher = longer pauses.
- `LT = LOG(10)` -- Precomputed for efficiency. Used in the big number formatter (line 610) to compute `LOG(WW) / LT`, which gives log base 10 of WW.
- `T$ = "Taipan"` -- This string appears in virtually every message to the player.
- `GOTO 10000` -- Jump to the full game initialization routine.

### Notes
- All numeric variables not explicitly initialized default to 0 in AppleSoft BASIC. The authors exploit this extensively -- variables like `CA` (cash), `BA` (bank), `DM` (damage), etc. are never explicitly zeroed.
- The `CLEAR` statement is redundant if the program is RUN fresh, but guards against leftover state from a previous run.

---

## SECTION 2: Delay / Keypress-Skip Routines (Lines 90-98)

### Purpose
Three short delay loops that pause the game for a set duration, but allow the player to skip the wait by pressing any key. These are called throughout the game after displaying messages. Line 92 is a full delay, line 94 is a half delay, and line 96 is also a half delay. Line 98 clears the keyboard buffer after the delay.

### Variables Used
| Variable | Role in this section |
|----------|---------------------|
| `II` | Loop counter |
| `T` | Base delay count (300) |
| `PEEK(-16384)` | Keyboard buffer check (>127 means key pressed) |

### Annotated Code

```basic
 90  REM
```
- Section marker comment.

```basic
 92  FOR II = 1 TO T:II = II + (PEEK(-16384) > 127) * 9999: NEXT II
```
- Loops from 1 to T (300). Each iteration, checks if a key is pressed. If so, `(PEEK(-16384) > 127)` evaluates to 1 (true), so `II = II + 9999` which exceeds T and exits the loop immediately. This is a **full-length delay with keypress skip**.

```basic
 94  FOR II = 1 TO T / 2:II = II + (PEEK(-16384) > 127) * 9999: NEXT II
```
- Same as line 92 but loops to T/2 (150). **Half-length delay with keypress skip.**

```basic
 96  FOR II = 1 TO T / 2:II = II + (PEEK(-16384) > 127) * 9999: NEXT II
```
- Identical to line 94. Another **half-length delay with keypress skip.** Often called after line 94 via `GOSUB 94` (which falls through to 96 and then to 98).

```basic
 98  POKE -16368,0: RETURN
```
- Clears the keyboard strobe (resets the keypress flag so the same keypress is not read twice). Returns from the subroutine.

### Notes
- `GOSUB 92` gives a full delay (T iterations + T/2 + T/2 = 2T total, because 92 falls through to 94, then 96, then 98).
- `GOSUB 94` gives a 3/4 delay (T/2 + T/2 = T iterations total).
- `GOSUB 96` gives a half delay (T/2 iterations).
- For Roblox: replace with `task.wait()` calls of appropriate duration (roughly 1-2 seconds for full, 0.5-1 second for half). Allow click/tap to skip.

---

## SECTION 3: Input Routines (Lines 100, 150)

### Purpose
Two core input routines used throughout the entire game:
- **Line 100 (GOSUB 100):** Character input -- waits for the player to press a key from the valid set `CH$` and returns the 1-based index in `CH%`.
- **Line 150 (GOSUB 150):** Numeric input -- gets a number from the player, with support for "A" (All) input via the `R1%` flag.

### Variables Used
| Variable | Role in this section |
|----------|---------------------|
| `CH$` | String of valid input characters (set before calling GOSUB 100) |
| `CH%` | Output: 1-based index of chosen character within CH$ |
| `WK$` | String input buffer for numeric input |
| `W` | Output: numeric value entered by player |
| `R1%` | Output: flag, 1 if player typed "A" (All), 0 otherwise |

### Annotated Code

```basic
 100  CALL 2560: RETURN
```
- `CALL 2560` -- Calls a machine-language routine that handles character input. This routine displays the valid characters from `CH$`, waits for the player to press one of them, and sets `CH%` to the 1-based position of that character within `CH$`. For example, if `CH$ = "YN"` and the player presses N, then `CH% = 2`.
- The `WU%` flag modifies this routine's behavior during the Wu visit prompt (line 1310) -- it likely changes the display format or accepted characters.

```basic
 150 WK$ = "" + "         ": CALL 2680:W = VAL(WK$):R1% = LEFT$(WK$,1) = "A": RETURN
```
- `WK$ = "" + "         "` -- Initializes the input buffer with spaces (the concatenation ensures it is a fresh string).
- `CALL 2680` -- Calls a machine-language routine that handles numeric input. The player types digits (or "A") into the buffer `WK$`. This routine handles backspace, cursor display, etc.
- `W = VAL(WK$)` -- Converts the string input to a number. If the input was "A" or non-numeric, VAL returns 0.
- `R1% = LEFT$(WK$,1) = "A"` -- String comparison: if the first character of input is "A", R1% is set to 1 (true), otherwise 0 (false). This is the "All" shortcut flag.
- **After calling GOSUB 150:** The calling code checks R1% and, if true, sets W to the maximum applicable value (e.g., all cash, all cargo, etc.).

### Notes
- The character input routine (CALL 2560) and numeric input routine (CALL 2680) are machine-language -- their exact implementation is not in the BASIC listing. For Roblox, implement as standard UI input handlers.
- The "A" (All) shortcut applies to ALL numeric inputs throughout the game: buying, selling, transferring, depositing, withdrawing, repairing, repaying debt, and borrowing.
- `CALL 2518` is a beep/error sound (referenced elsewhere). `CALL 2521` is a success/positive sound. `CALL 2512` is an alert/alarm sound. `CALL 2524` is a short error beep.

---

## SECTION 4: Display Routines (Lines 200-270, 300-360, 400-490)

### Purpose
These routines draw the main game screen, update the status display, and manage the text window for messages.

### Sub-sections

#### Lines 200-270: Draw the Main Screen Frame

Draws the full screen layout including the firm name, port artwork, cargo labels, date/debt/status labels, and the UI border graphics.

### Variables Used
| Variable | Role in this section |
|----------|---------------------|
| `FS$` | Control code: clear/reset full screen |
| `HM$` | Control code: home cursor (CHR$(16)) |
| `CS$` | Control code: set color scheme 0 (normal text) |
| `CA$` | Control code: set color scheme 1 (highlight) |
| `CG$` | Control code: set color scheme 2 (graphics/border) |
| `H$` | Player's firm name |
| `CO$(IJ)` | Commodity name for good IJ |
| `IV$` | Control code: inverse video on |
| `NV$` | Control code: normal video (inverse off) |
| `WS` | Warehouse space in use |
| `WC` | Warehouse capacity (10,000) |
| `II, IJ` | Loop counters |

### Annotated Code

```basic
 200  REM
```
- Section marker.

```basic
 210  PRINT FS$;HM$;CS$; SPC(12 - LEN(H$) / 2): PRINT "Firm: ";CA$;H$;CS$;", ";
     :X = USR(1): PRINT
```
- `FS$;HM$;CS$` -- Clears screen, homes cursor, sets normal color scheme.
- `SPC(12 - LEN(H$) / 2)` -- Centers the firm name display by printing leading spaces.
- `"Firm: ";CA$;H$;CS$` -- Prints "Firm: " then the firm name in highlight color, then reverts to normal.
- `X = USR(1)` -- **USR(1): Draws the port/ship artwork** in the designated area of the screen. The specific artwork depends on the current port.
- `PRINT` -- Newline.

```basic
 220  VTAB 2: PRINT CG$;"[";: & 45,26: PRINT "]"
     : FOR II = 1 TO 5: PRINT "!"; TAB(28);"!": NEXT II
     : PRINT "(";: & 61,26: PRINT ")"
     : FOR II = 1 TO 5: PRINT "!"; TAB(28);"!": NEXT II
     : PRINT "<";: & 58,26: PRINT ">";CS$
```
- Draws the rectangular border box for the ship/port artwork area using custom characters.
- `CG$` -- Sets the graphics color scheme for the border.
- `& 45,26` -- Ampersand command: draws a horizontal line of 26 characters (character code 45 = "-") for the top border.
- The `[`, `]`, `(`, `)`, `<`, `>` characters are corner pieces of the box.
- `!` characters with `TAB(28)` create the vertical side borders.
- `& 61,26` -- Middle horizontal divider.
- `& 58,26` -- Bottom horizontal border.
- `CS$` -- Reverts to normal color scheme.

```basic
 230  VTAB 3: HTAB 2:X = USR(1) + USR(2): VTAB 4: HTAB 21
     : PRINT "In use:": VTAB 6: HTAB 21: PRINT "Vacant:"
     : VTAB 9: HTAB 2: PRINT "Hold           Guns";
```
- `X = USR(1) + USR(2)` -- **USR(1) and USR(2): Draw the ship/port graphics** inside the border box. The addition is just a way to call both; return values are discarded.
- Prints the labels "In use:", "Vacant:", "Hold", and "Guns" in their fixed screen positions.

```basic
 240  FOR II = 3 TO 9 STEP 6: FOR IJ = 1 TO 4
     : VTAB II + IJ: HTAB 5: PRINT LEFT$(CO$(IJ),7);: NEXT IJ,II
```
- Prints commodity names in two columns: once at rows 4-7 (warehouse area, II=3) and once at rows 10-13 (ship hold area, II=9).
- `LEFT$(CO$(IJ),7)` -- Truncates commodity names to 7 characters for display alignment.

```basic
 250  VTAB 3: HTAB 33: PRINT "Date"
     : VTAB 6: HTAB 31:X = USR(3)
     : VTAB 9: HTAB 33: PRINT "Debt"
     : VTAB 12: HTAB 29: PRINT " Ship status":
```
- Prints the right-column labels: "Date", "Debt", "Ship status".
- `X = USR(3)` -- **USR(3): Displays the port location name** in the right column area.

```basic
 260  VTAB 16: HTAB 1: PRINT CG$;: & 45,40: PRINT CS$
```
- Draws a horizontal divider line across the full screen width at row 16, separating the status area from the message area below.

```basic
 270  RETURN
```
- Returns from the screen frame drawing routine.

#### Lines 300-360: Update Status Values (GOSUB 300)

Updates the dynamic values on screen: date, location, debt, ship status percentage, warehouse usage, cargo quantities, cash, bank, guns, and hold space.

### Variables Used
| Variable | Role in this section |
|----------|---------------------|
| `YE` | Current year |
| `MO` | Current month (1-12) |
| `IV$`/`NV$` | Inverse video on/off |
| `LO` | Current port index |
| `LO$()` | Port name array |
| `DW` | Debt to Elder Brother Wu |
| `WW` | Scratch: used for debt display, then ship status percentage |
| `WW$` | Output of big number formatter |
| `DM` | Ship damage points |
| `SC` | Ship total capacity |
| `W` | Scratch: ship status bracket (0-5) |
| `ST$()` | Status label array ("Critical" through "Perfect") |
| `WS` | Warehouse space in use |
| `WC` | Warehouse capacity |
| `ST(I,J)` | Cargo array (I=1 warehouse, I=2 ship; J=1-4 goods) |
| `CA` | Cash |
| `BA` | Bank balance |
| `GN` | Number of guns |
| `MW` | Available hold space |

### Annotated Code

```basic
 310  VTAB 4: HTAB 30: PRINT "15          ";YE
     : VTAB 4: HTAB 33: PRINT IV$; MID$("JanFebMarAprMayJunJulAugSepOctNovDec",
     (MO - 1) * 3 + 1, 3);NV$
```
- Prints the date. First prints "15" and the year (the day is always shown as the 15th -- simplified calendar).
- `MID$("JanFeb...", (MO-1)*3+1, 3)` -- Extracts the 3-letter month abbreviation from a concatenated string. MO=1 gives "Jan", MO=2 gives "Feb", etc. Displayed in inverse video.

```basic
 311  VTAB 7: HTAB 31: PRINT "              "
     : VTAB 7: HTAB 35 - LEN(LO$(LO)) / 2 + .5: PRINT IV$;LO$(LO);NV$
```
- Clears the location line, then prints the current port name centered in inverse video.

```basic
 312  VTAB 10: HTAB 29: PRINT "                "
     : VTAB 10:WW = DW: GOSUB 600: HTAB 35 - LEN(WW$) / 2: PRINT IV$;WW$;NV$
```
- Clears the debt line, formats the debt value using the big number formatter (GOSUB 600), then prints it centered in inverse video.
- `WW = DW` -- Loads current debt into WW for the formatter.

```basic
 313 WW = 100 - INT(DM / SC * 100 + .5):WW = WW * (WW > 0)
     :W = INT(WW / 20): VTAB 13: HTAB 30: IF W < 2 THEN PRINT IV$;
```
- **Ship status calculation:**
  - `WW = 100 - INT(DM / SC * 100 + .5)` -- Calculates ship health as a percentage (100% = no damage). Rounds to nearest integer.
  - `WW = WW * (WW > 0)` -- Clamps to 0 minimum. If WW is negative, `(WW > 0)` is 0, so WW becomes 0.
  - `W = INT(WW / 20)` -- Divides into brackets of 20%: 0=Critical (0-19%), 1=Poor (20-39%), 2=Fair (40-59%), 3=Good (60-79%), 4=Prime (80-99%), 5=Perfect (100%).
  - `IF W < 2 THEN PRINT IV$` -- If status is Critical or Poor (W=0 or W=1), display in inverse video as a warning.

```basic
 314  PRINT ST$(W);":";WW;: IF PEEK(36) > 30 THEN PRINT TAB(40);" ";
```
- Prints the status label and percentage, e.g., "Good:78". If the cursor is past column 30, prints padding to prevent display overflow.

```basic
 315  PRINT NV$;
```
- Ends inverse video mode if it was started.

```basic
 316  VTAB 5: HTAB 22: PRINT "      ";: HTAB 22: PRINT WS
     : VTAB 7: HTAB 22: PRINT "     ";: HTAB 22: PRINT WC - WS
```
- Prints warehouse "In use" (WS) and "Vacant" (WC - WS) values.

```basic
 320  POKE 32,12: FOR II = 1 TO 2
     : POKE 33,(II - 1) * 9 + 6:IK = II * 6 - 3: POKE 34,IK: POKE 35,IK + 4
     : PRINT HM$: FOR IJ = 1 TO 4: VTAB IK + IJ: HTAB 1: PRINT ST(II,IJ);
     : NEXT IJ,II
```
- **Prints cargo quantities for warehouse (II=1) and ship hold (II=2).**
- `POKE 32,12` -- Sets left margin to column 12.
- `POKE 33,...` / `POKE 34,...` / `POKE 35,...` -- Sets the text window width, top, and bottom for each column.
- `PRINT HM$` -- Homes cursor within the text window.
- `ST(II,IJ)` -- Prints the quantity of good IJ in storage location II.
- The nested loop prints all 4 goods for warehouse (II=1), then all 4 for ship hold (II=2).

```basic
 330  PRINT FS$: VTAB 15: HTAB 1:WW = CA: GOSUB 600
     : PRINT "Cash:";WW$; TAB(21);:WW = BA: GOSUB 600
     : PRINT "Bank:";WW$; TAB(40);" "
     : VTAB 9: HTAB 22: PRINT GN;: HTAB 7: PRINT "        ";: HTAB 7
```
- `PRINT FS$` -- Resets the text window to full screen.
- Formats and prints Cash and Bank values using the big number formatter.
- Prints the gun count (GN) at the guns display position.

```basic
 340  IF MW < 0 THEN PRINT IV$;"Overload";NV$
```
- If available hold space is negative (overloaded), displays "Overload" warning in inverse video.

```basic
 350  IF MW >= 0 THEN PRINT MW;
```
- If not overloaded, prints the available hold space number.

```basic
 360  RETURN
```
- Returns from status update routine.

#### Lines 400-410: Clear Message Area (GOSUB 400)

```basic
 400  REM
 410  POKE 32,0: POKE 33,40: POKE 34,18: POKE 35,24: PRINT HM$;: RETURN
```
- Resets the text window to the bottom portion of the screen (rows 18-24, full width 40 columns).
- `PRINT HM$` -- Homes cursor within this window, effectively clearing the message area.
- This is called before printing any message to the player.

#### Lines 480-490: USR Display Calls

```basic
 480  VTAB 17: HTAB 1:X = USR(4): RETURN
```
- **USR(4): Displays the port arrival artwork/banner** at row 17. Called when arriving at a port.

```basic
 490  VTAB 17: HTAB 1:X = USR(5): RETURN
```
- **USR(5): Displays the "sailing" / departure artwork** at row 17. Called when the ship is traveling between ports.

### Notes
- The display system uses a fixed 40-column, 24-row text screen. The top 16 rows are the status display; rows 17-24 are the message/interaction area.
- `POKE 32-35` manipulates AppleSoft's text window, restricting where PRINT output goes. This prevents messages from overwriting the status area.
- For Roblox: These translate to UI frame updates. The status panel and message panel should be separate UI elements.

---

## SECTION 5: Bank Deposit/Withdraw (Lines 500-590)

### Purpose
Handles depositing cash into the bank and withdrawing cash from the bank. Only available in Hong Kong.

### Variables Used
| Variable | Role |
|----------|------|
| `CA` | Cash on hand |
| `BA` | Bank balance |
| `W` | Amount to deposit or withdraw |
| `R1%` | "All" flag from numeric input |
| `T$` | "Taipan" |

### Annotated Code

```basic
 500  REM
```
- Section marker.

```basic
 510  GOSUB 400:X = USR(6): GOSUB 150: IF R1% THEN W = CA
```
- Clears message area. **USR(6): Displays "How much will you deposit?"** prompt.
- Gets numeric input. If player typed "A" (All), sets W to all cash.

```basic
 530  IF CA >= W THEN CA = CA - W:BA = BA + W: GOSUB 300: GOTO 550
```
- If player has enough cash, transfers W from cash to bank. Updates display. Falls through to withdrawal.

```basic
 540  PRINT : PRINT : PRINT T$;:X = USR(8): PRINT CA
     : PRINT "in cash.": CALL 2518: GOSUB 94: GOTO 510
```
- **Error case:** Player tried to deposit more than they have. **USR(8): Displays ", you have only "** message. `CALL 2518` plays error beep. Waits, then loops back to deposit prompt.

```basic
 550  GOSUB 400:X = USR(7): GOSUB 150: IF R1% THEN W = BA
```
- Clears message area. **USR(7): Displays "How much will you withdraw?"** prompt.
- Gets numeric input. If "All", sets W to entire bank balance.

```basic
 570  IF BA >= W THEN BA = BA - W:CA = CA + W: GOSUB 300: GOTO 590
```
- If bank has enough, transfers W from bank to cash. Updates display. Goes to return.

```basic
 580  PRINT : PRINT : PRINT T$;:X = USR(8): PRINT BA
     : PRINT "in the bank.": CALL 2518: GOSUB 94: GOTO 550
```
- **Error case:** Tried to withdraw more than bank balance. Shows error, loops back.

```basic
 590  RETURN
```
- Returns to caller (the main port menu).

### Notes
- Depositing 0 is valid and just falls through silently.
- The bank earns 0.5% interest per month (compounded at line 1010), making it a safe investment vehicle.
- For Roblox: validate amounts server-side. Reject negative values.

---

## SECTION 6: Big Number Formatter (Lines 600-690)

### Purpose
Formats large numbers for display. Numbers under 1 million are shown as plain integers. Numbers 1 million and above are shown with 3-4 significant digits plus a suffix (Thousand, Million, Billion, Trillion).

### Variables Used
| Variable | Role |
|----------|------|
| `WW` | Input: the number to format |
| `WW$` | Output: the formatted string |
| `II` | Scratch: number of digits (log10 of WW) |
| `IJ` | Scratch: magnitude bracket (3, 6, 9, or 12) |
| `IK` | Scratch: rounding factor |
| `W$` | Suffix string |
| `LT` | Precomputed LOG(10) |

### Annotated Code

```basic
 600  IF WW < 1E6 THEN WW$ = STR$(INT(WW)): RETURN
```
- If the number is under 1 million, simply convert to integer string and return. No suffix needed.

```basic
 610 II = INT(LOG(WW) / LT):IJ = INT(II / 3) * 3
    :IK = 10 ^ (II - 2):WW$ = LEFT$(STR$(INT(WW / IK + .5) * IK / 10 ^ IJ), 4) + " "
```
- `II = INT(LOG(WW) / LT)` -- Calculates the number of digits minus 1 (floor of log base 10). E.g., 1,500,000 gives II=6.
- `IJ = INT(II / 3) * 3` -- Snaps to the nearest magnitude bracket: 3 (Thousand), 6 (Million), 9 (Billion), 12 (Trillion).
- `IK = 10 ^ (II - 2)` -- Rounding factor: rounds to 3 significant digits.
- The complex expression: divides by IK, rounds, multiplies back, divides by 10^IJ to get the display value, then takes the first 4 characters.
- Appends a space separator before the suffix.

```basic
 620  IF IJ = 3 THEN W$ = "Thousand"
 630  IF IJ = 6 THEN W$ = "Million"
 640  IF IJ = 9 THEN W$ = "Billion"
 650  IF IJ = 12 THEN W$ = "Trillion"
```
- Selects the appropriate suffix based on magnitude bracket.

```basic
 680 WW$ = WW$ + W$
 690  RETURN
```
- Concatenates the suffix to the formatted number string and returns.

### Notes
- Example: WW = 1,534,000 -> II=6, IJ=6, IK=10000 -> "1.53 Million" (approximately).
- The formatter handles up to Trillions. Values beyond 999 Trillion would display incorrectly but are unlikely in normal gameplay.
- For Roblox: implement a `formatBigNumber()` function. See `BigNumber.lua` in the design document.

---

## SECTION 7: Main Loop Entry -- Time Advance and Interest (Lines 1000-1020)

### Purpose
This is the main game loop entry point. When the player arrives at any port (including the initial arrival), this code advances time by one month, compounds bank interest and debt, and checks for January (new year) events.

### Variables Used
| Variable | Role |
|----------|------|
| `D` | Destination port (0 on initial arrival) |
| `BA` | Bank balance |
| `DW` | Debt to Elder Brother Wu |
| `TI` | Total months elapsed |
| `MO` | Current month (1-12) |
| `LO` | Current port (set to destination) |
| `YE` | Current year |
| `EC` | Enemy HP pool base (increases each January) |
| `ED` | Enemy damage base (increases each January) |
| `BP%(I,J)` | Base price matrix (drifts upward each January) |

### Annotated Code

```basic
 1000  REM
```
- **Main loop entry point.** All port arrivals flow here.

```basic
 1010  IF D <> 0 THEN GOSUB 490: GOSUB 400:X = USR(9): PRINT LO$(D)
      : GOSUB 96:BA = INT(BA + BA * .005):DW = INT(DW + DW * .1)
      :TI = TI + 1:MO = MO + 1:LO = D
```
- `IF D <> 0` -- Skips this block on the very first arrival (D=0 at game start). After that, D is always 1-7.
- `GOSUB 490` -- Shows the sailing/departure artwork.
- `GOSUB 400:X = USR(9): PRINT LO$(D)` -- Clears message area. **USR(9): Displays "Arriving at "** message. Prints the destination port name.
- `GOSUB 96` -- Half-delay pause.
- `BA = INT(BA + BA * .005)` -- **Bank interest: 0.5% per month**, compounded. Truncated to integer.
- `DW = INT(DW + DW * .1)` -- **Debt interest: 10% per month**, compounded. Truncated to integer. **This is extremely aggressive -- debt doubles roughly every 7 months.**
- `TI = TI + 1` -- Increment total months elapsed.
- `MO = MO + 1` -- Increment current month.
- `LO = D` -- Set current location to the destination.

```basic
 1020  IF MO > 12 THEN YE = YE + 1:MO = 1:EC = EC + 10:ED = ED + .5
      : FOR I = 1 TO 7: FOR J = 1 TO 4:BP%(I,J) = BP%(I,J) + FN R(2): NEXT J,I
```
- **January (new year) check.** If month exceeds 12:
  - `YE = YE + 1` -- Advance year.
  - `MO = 1` -- Reset to January.
  - `EC = EC + 10` -- **Enemy HP pool increases by 10.** Starts at 20, so year 2 = 30, year 3 = 40, etc. Pirates get tougher each year.
  - `ED = ED + .5` -- **Enemy damage base increases by 0.5.** Starts at 0.5, so year 2 = 1.0, etc. Pirates hit harder each year.
  - `BP%(I,J) = BP%(I,J) + FN R(2)` -- Each base price in every port increases by 0 or 1 randomly. **Prices drift upward over time.** This affects all subsequent price calculations.

```basic
 1030  GOSUB 400: GOSUB 480: GOSUB 300: IF LO <> 1 THEN 1500
```
- Clears message area. Shows port arrival artwork (GOSUB 480). Updates status display (GOSUB 300).
- `IF LO <> 1 THEN 1500` -- **If not in Hong Kong, skip all Hong Kong-only events** and jump to the ship upgrade/gun purchase section. Hong Kong (port 1) is the only port with the bank, Wu, Li Yuen, warehouse, and repair.

### Notes
- **Critical game balance numbers:**
  - Bank interest: **0.5% per month** (approximately 6.2% per year compounded)
  - Debt interest: **10% per month** (approximately 214% per year compounded!)
  - EC starts at 20, +10/year
  - ED starts at 0.5, +0.5/year
  - Base prices drift by 0 or 1 per good per port per year (very slight inflation)
- `TI` starts at 1 (set at line 10150). The first voyage increments it to 2.
- The `D <> 0` guard means no interest/time-advance happens on the very first port visit (game start).

---

## SECTION 8: Hong Kong Arrival -- Li Yuen Protection Offer (Lines 1040-1100)

### Purpose
When arriving in Hong Kong, the player may be offered Li Yuen's pirate protection. Li Yuen's fleet will let protected players pass safely; unprotected players face dangerous encounters at sea.

### Variables Used
| Variable | Role |
|----------|------|
| `LI` | Li Yuen protection flag (0 = unprotected, non-zero = protected) |
| `CA` | Cash on hand |
| `TI` | Total months elapsed |
| `WW` | Scratch: used for protection cost base |
| `W` | Scratch: divisor for cost formula |
| `I` | Protection cost (amount deducted from cash) |

### Annotated Code

```basic
 1040  IF LI <> 0 OR CA = 0 THEN 1120
```
- **Skip conditions:** If already protected (`LI <> 0`) OR if the player has no cash (`CA = 0`), skip the offer entirely. Jump to ship repair.

```basic
 1050 WW = 0:W = 1.8: IF TI > 12 THEN WW = FN R(1000 * TI) + 1000 * TI:W = 1
```
- **Cost formula setup based on game stage:**
  - **Early game (TI <= 12):** `WW = 0`, `W = 1.8`. The cost will be just `FN R(CA / 1.8)` -- a random fraction of the player's cash divided by 1.8. Maximum cost is roughly 55% of cash.
  - **Late game (TI > 12):** `WW = FN R(1000 * TI) + 1000 * TI`, `W = 1`. The cost adds a large time-scaled component. `WW` is a random value between `1000*TI` and `2000*TI - 1`. The cost will be `FN R(CA / 1) + WW`, which is `FN R(CA) + FN R(1000*TI) + 1000*TI`. **Late-game protection can cost most of the player's cash plus a huge time-scaled amount.**

```basic
 1060 I = FN R(CA / W) + WW:WW = I: GOSUB 600: GOSUB 400
     :X = USR(10): PRINT WW$;" ";:X = USR(11):CH$ = "NY": GOSUB 100
     : IF CH% <> 2 THEN 1120
```
- `I = FN R(CA / W) + WW` -- **Final protection cost.** Random value from 0 to `CA/W - 1`, plus the base `WW`.
- `WW = I: GOSUB 600` -- Formats the cost for display.
- **USR(10): Displays "Li Yuen asks "** (the protection cost prompt beginning). **USR(11): Displays " in donation. Will you pay?"** (the prompt ending).
- `CH$ = "NY": GOSUB 100` -- Gets Y/N input. CH%=1 means N (No), CH%=2 means Y (Yes).
- `IF CH% <> 2 THEN 1120` -- If player says No (or anything other than Yes), skip to ship repair.

```basic
 1065 LI = 1:CA = CA - I: IF CA > 0 THEN 1100
```
- Player said Yes. `LI = 1` -- Set protection flag. `CA = CA - I` -- Deduct the cost.
- If cash remains positive, jump to line 1100 (update display and continue).

```basic
 1070  GOSUB 400: PRINT T$;:X = USR(12): CALL 2512
     : PRINT : PRINT :X = USR(13):CH$ = "YN": GOSUB 100
```
- **Cash went negative** (protection cost exceeded cash). This means the player committed to pay but did not have enough.
- **USR(12): Displays ", you do not have enough cash!!"** alert. `CALL 2512` plays alarm sound.
- **USR(13): Displays "Do you want Elder Brother Wu to make up the difference?"** Y/N prompt.

```basic
 1080  IF CH% = 1 THEN DW = DW - CA:CA = 0: GOSUB 400
     :X = USR(14): CALL 2521: GOSUB 94
```
- Player says Yes (CH%=1 in "YN" string = Y). **Wu covers the shortfall.**
- `DW = DW - CA` -- Since CA is negative, this ADDS the absolute value to debt. E.g., if CA = -500, then DW = DW - (-500) = DW + 500.
- `CA = 0` -- Cash zeroed out.
- **USR(14): Displays "Elder Brother Wu has paid the difference."** `CALL 2521` plays positive sound.

```basic
 1090  IF CH% = 2 THEN CA = 0:LI = 0: GOSUB 400:X = USR(15)
     : PRINT T$;".": CALL 2518: GOSUB 94
```
- Player says No (CH%=2 = N). **Backs out of the deal.**
- `CA = 0` -- Cash zeroed (they already committed the cash). `LI = 0` -- Protection revoked.
- **USR(15): Displays "Very well. The deal is off, "** followed by "Taipan.". Error beep.

```basic
 1100  GOSUB 300
```
- Updates the status display to reflect changes to cash, debt, and protection.

### Notes
- **Probability:** The offer appears every Hong Kong arrival when the player is unprotected and has cash. It is not random.
- **Early game cost (TI <= 12):** `FN R(CA / 1.8)` = random 0 to ~55% of cash. Average cost: ~28% of cash.
- **Late game cost (TI > 12):** `FN R(CA) + FN R(1000*TI) + 1000*TI`. The `1000*TI` base alone makes this very expensive. At TI=24 (2 years in), the minimum cost is 24,000 plus a random fraction of cash.
- If the player cannot fully afford it but says Yes, they get a choice to have Wu cover the difference (adding to debt) or cancel (losing their cash AND the protection).
- Protection randomly expires at line 2310 with a 1-in-20 chance per port visit.
- For Roblox: present as a dialog. The cost formula must exactly match for faithful game balance.

---

## SECTION 9: Hong Kong Arrival -- Ship Repair (Lines 1120-1160)

### Purpose
If the player's ship is damaged and they are in Hong Kong, they can pay for repairs. The cost scales with ship size and game progression. Partial repairs are supported.

### Variables Used
| Variable | Role |
|----------|------|
| `DM` | Ship damage points |
| `SC` | Ship total capacity |
| `TI` | Total months elapsed |
| `BR` | Repair cost per unit of damage |
| `WW` | Scratch: damage percentage, then total repair cost |
| `W` | Amount player chooses to pay |
| `CA` | Cash on hand |
| `R1%` | "All" flag |

### Annotated Code

```basic
 1120  IF DM = 0 THEN 1210
```
- If ship is undamaged, skip repairs entirely. Jump to Wu warning check.

```basic
 1130  GOSUB 400: PRINT T$;:X = USR(16):CH$ = "YN": GOSUB 100
     : IF CH% = 2 THEN 1210
```
- **USR(16): Displays ", do you wish to repair your ship?"** Y/N prompt.
- `CH$ = "YN"`: CH%=1 means Y (Yes), CH%=2 means N (No).
- If No, skip to Wu warning.

```basic
 1140 BR = INT((FN R(60 * (TI + 3) / 4) + 25 * (TI + 3) / 4) * SC / 50)
```
- **Repair cost per unit of damage:**
  - `FN R(60 * (TI + 3) / 4)` -- Random component: 0 to `60*(TI+3)/4 - 1`.
  - `25 * (TI + 3) / 4` -- Fixed base component.
  - Sum is multiplied by `SC / 50` -- scales with ship size (base SC=60, so multiplier starts at 1.2).
  - `INT(...)` -- Truncated to integer.
  - **Example at game start (TI=1, SC=60):** `INT((FN R(60) + 25) * 1.2)` = roughly 30 to 102 per damage unit.
  - **Late game (TI=24, SC=200):** `INT((FN R(405) + 168.75) * 4)` = roughly 675 to 2295 per damage unit.

```basic
 1142 WW = INT(DM / SC * 100 + .5)
```
- Calculates damage percentage for display. Rounded to nearest integer.

```basic
 1145  GOSUB 400:X = USR(17): PRINT WW;"% damaged."
     : PRINT :WW = BR * DM + 1: GOSUB 600:X = USR(18): PRINT WW$;","
```
- **USR(17): Displays "Your ship is "** prefix. Prints the damage percentage.
- `WW = BR * DM + 1` -- **Total repair cost** = cost per unit times damage points, plus 1 (ensures non-zero cost).
- Formats total cost with big number formatter.
- **USR(18): Displays "Taipan. It will cost "** followed by the formatted cost.

```basic
 1150 X = USR(19): GOSUB 150: IF R1% = 1 THEN W = BR * DM + 1
     : IF CA < W THEN W = CA
```
- **USR(19): Displays "How much will you spend on repairs?"** prompt.
- Gets numeric input. If "All", sets W to full repair cost, but caps at available cash.

```basic
 1155  IF CA < W THEN GOSUB 400: PRINT T$;:X = USR(12): GOSUB 96: GOTO 1142
```
- If player entered more than they have, shows "you do not have enough cash!!" error and loops back.

```basic
 1160 WW = INT(W / BR + .5):DM = DM - WW:CA = CA - W
     :DM = INT(DM * (DM > 0)): GOSUB 300: GOSUB 400
```
- `WW = INT(W / BR + .5)` -- Calculates damage repaired = payment divided by cost-per-unit, rounded to nearest.
- `DM = DM - WW` -- Reduces damage.
- `CA = CA - W` -- Deducts payment.
- `DM = INT(DM * (DM > 0))` -- Clamps damage to 0 minimum. If DM went negative, it becomes 0.
- Updates display and clears message area.

### Notes
- **Partial repairs are supported.** The player can spend any amount up to their cash.
- The +1 in the total cost formula (`BR * DM + 1`) ensures there is always a minimum repair cost of 1.
- Repair cost escalates significantly over time due to the `(TI + 3) / 4` factor.
- Ship upgrades (line 1630) also fully repair the ship as a side benefit.

---

## SECTION 10: Hong Kong Arrival -- Wu Warning and Visit (Lines 1210-1460)

### Purpose
This multi-part section handles:
1. **Wu's Warning (1210-1240):** A one-time intimidation event when debt is high.
2. **Wu's Visit (1300-1450):** The player can repay debt, borrow more, or receive an emergency loan if broke.
3. **Wu's Enforcers (1460):** After the visit, if debt is very high, Wu's men may rob the player.

### Sub-section: Wu's Warning (Lines 1210-1240)

### Variables Used
| Variable | Role |
|----------|------|
| `DW` | Debt to Elder Brother Wu |
| `WN` | Wu warning flag (1 = warning already given) |
| `D` | Destination (0 on first arrival, non-zero after) |
| `T$` | "Taipan" |

### Annotated Code

```basic
 1210  IF DW < 10000 OR WN OR D = 0 THEN 1300
```
- **Skip conditions (any one triggers skip):**
  - `DW < 10000` -- Debt is below the warning threshold of 10,000.
  - `WN` -- Warning already given (WN is non-zero/truthy).
  - `D = 0` -- This is the very first port arrival (game start).
- If all conditions pass, the warning fires.

```basic
 1220  GOSUB 400: PRINT "Elder Brother Wu has sent "; FN R(100) + 50;
     " braves": PRINT "to escort you to the Wu mansion, ";T$;"."
     :WN = 1: GOSUB 94
```
- Displays the intimidation message. Wu sends 50-149 braves (random) to escort the player.
- `WN = 1` -- Sets the flag so this warning only happens once per game.
- Pauses for player to read.

```basic
 1230  GOSUB 400:X = USR(20): GOSUB 92
```
- **USR(20): Displays the Wu mansion narrative text** (first part). Full delay.

```basic
 1240  GOSUB 400:X = USR(21): PRINT T$;".";: GOSUB 92
```
- **USR(21): Displays the Wu mansion narrative text** (second part), ending with "Taipan." Full delay.

### Sub-section: Wu's Visit -- Debt Repayment, Borrowing, and Bankruptcy (Lines 1300-1450)

### Variables Used
| Variable | Role |
|----------|------|
| `CA` | Cash |
| `BA` | Bank balance |
| `DW` | Debt |
| `GN` | Number of guns |
| `ST(I,J)` | Cargo (I=1 warehouse, I=2 ship; J=1-4) |
| `W` | Scratch: total assets check, then input amount |
| `BL%` | Bankruptcy counter |
| `I` | Scratch: loan amount |
| `J` | Scratch: repayment amount |
| `R1%` | "All" flag |
| `WU%` | Wu prompt flag (modifies input routine behavior) |

### Annotated Code

```basic
 1300  REM
```
- Section marker.

```basic
 1310  GOSUB 400:X = USR(22):CH$ = "NY":WU% = 1: GOSUB 100:WU% = 0
     : IF CH% <> 2 THEN 1500
```
- **USR(22): Displays "Do you wish to visit Elder Brother Wu?"** prompt.
- `WU% = 1` -- Sets the Wu prompt flag, which modifies the input routine behavior (likely changing display formatting). Reset to 0 immediately after input.
- `CH$ = "NY"`: CH%=1 means N, CH%=2 means Y.
- If player says No, skip to ship upgrade/gun purchase section (line 1500).

```basic
 1320 W = 0: FOR I = 1 TO 2: FOR J = 1 TO 4:W = W + ST(I,J)
     : NEXT J,I: IF CA OR BA OR W OR GN THEN 1360
```
- **Bankruptcy check.** Sums all cargo in warehouse and ship. Checks if player has ANY assets: cash, bank, cargo, or guns.
- If the player has ANY assets at all, jumps to the normal debt repayment/borrowing at line 1360.
- If player has NOTHING, falls through to the emergency loan (bankruptcy).

```basic
 1330 BL% = BL% + 1:I = INT(FN R(1500) + 500)
     :J = FN R(2000) * BL% + 1500
     : GOSUB 400: PRINT "Elder Brother is aware of your plight,  ";T$;"."
     ;"  He is willing to loan you an   additional ";I
     ;" if you will pay back"
```
- `BL% = BL% + 1` -- Increment bankruptcy counter. **Each subsequent emergency loan has worse terms.**
- `I = INT(FN R(1500) + 500)` -- **Loan amount:** random 500 to 1999.
- `J = FN R(2000) * BL% + 1500` -- **Repayment amount:** random up to `2000 * BL%`, plus 1500. **Brutally scales with bankruptcy count.** First bankruptcy: 1500-3499 repayment. Second: 1500-5499. Third: 1500-7499. Etc.
- Displays the offer.

```basic
 1340  PRINT J;". Are you willing, ";T$;"? ";:CH$ = "YN": GOSUB 100
     : IF CH% = 2 THEN GOSUB 400: PRINT : PRINT "Very well, Taipan, the game is over!"
     : CALL 2512: GOTO 2698
```
- Prints the repayment amount and asks Y/N.
- **If player refuses (CH%=2 = N): GAME OVER.** Refusing Wu's loan when broke ends the game. Jumps to score display (line 2698).

```basic
 1350 CA = CA + I:DW = DW + J: GOSUB 400: PRINT "Very well, ";T$
     ;".  Good joss!!": CALL 2521: GOSUB 300: GOSUB 96: GOTO 1500
```
- Player accepts. Cash increases by loan amount. **Debt increases by the REPAYMENT amount** (which is always much higher than the loan). Updates display. Jumps to ship upgrade section.

```basic
 1360  IF DW = 0 OR CA = 0 THEN 1400
```
- If no debt, or no cash, skip debt repayment and go to borrowing.

```basic
 1370  GOSUB 400:X = USR(23): GOSUB 150: IF R1% THEN W = CA
     : IF CA > DW THEN W = DW
```
- **USR(23): Displays "How much do you wish to repay?"** Gets numeric input.
- If "All", sets W to all cash, but caps at total debt (no overpaying).

```basic
 1380  IF CA >= W THEN CA = CA - W:DW = DW - W: GOSUB 300: GOTO 1400
```
- If player can afford it, deducts from cash and debt. Updates display. Continues to borrowing.

```basic
 1390  PRINT : PRINT : PRINT T$;", you have only ";CA
     : PRINT "in cash.": CALL 2518: GOSUB 94: GOTO 1370
```
- Error: tried to repay more than they have. Shows error, loops back.

```basic
 1400  GOSUB 400:X = USR(24): GOSUB 150: IF R1% THEN W = 2 * CA
```
- **USR(24): Displays "How much do you wish to borrow?"** Gets numeric input.
- If "All", sets W to **2 times current cash** (the maximum Wu will lend).

```basic
 1420  IF CA * 2 >= W THEN CA = CA + W:DW = DW + W: GOSUB 300: GOTO 1450
```
- **Borrowing limit: up to 2x current cash.** If the request is within limit, adds to both cash and debt equally.

```basic
 1430  PRINT : PRINT : PRINT "He won't loan you so much, ";T$;"!"
     : CALL 2518: GOSUB 94: GOTO 1400
```
- Error: requested too much. Wu refuses. Loops back.

```basic
 1450  REM
```
- Marker between borrowing and enforcers.

### Sub-section: Wu's Enforcers (Line 1460)

```basic
 1460  IF DW > 20000 AND NOT(FN R(5)) THEN GOSUB 400
     : PRINT "Bad joss!!": PRINT FN R(3) + 1;" of your bodyguards have been killed"
     : PRINT "by cutthroats and you have been robbed  of all your cash, ";T$;"!!"
     : CALL 2512:CA = 0: GOSUB 300: GOSUB 94
```
- **Trigger:** Debt exceeds 20,000 AND `NOT(FN R(5))` -- `FN R(5)` returns 0-4; NOT(0)=1 (true), NOT(non-zero)=0. So this fires when `FN R(5) = 0`, which is **1-in-5 chance (20%)**.
- **Effect:** 1-3 bodyguards killed (narrative only), ALL cash stolen (`CA = 0`). Debt is unchanged.
- `CALL 2512` plays alarm sound.

### Notes
- **Wu visit order:** Warning (one-time) -> Visit (repay/borrow) -> Enforcers. All in sequence.
- **Bankruptcy is the only path to emergency loans.** The player must have literally zero: no cash, no bank, no cargo anywhere, no guns.
- **Emergency loan terms are predatory:** The repayment is always much higher than the loan, and it gets worse each time.
- **Refusing the emergency loan is game over.** This is the only forced game-ending choice.
- **Enforcers always fire after the Wu visit** (line 1460 follows the Wu visit block). They do not fire independently at random times.
- **Critical balance number:** Debt threshold for enforcers is 20,000.

---

## SECTION 11: Port Arrival -- Ship Upgrade and Gun Purchase (Lines 1500-1740)

### Purpose
At any port, the player may be offered a ship upgrade (more capacity + full repair) or a gun purchase. Both are probabilistic and cost-gated.

### Variables Used
| Variable | Role |
|----------|------|
| `I` | Cost of the upgrade or gun |
| `TI` | Total months elapsed |
| `SC` | Ship total capacity |
| `DM` | Ship damage |
| `CA` | Cash |
| `MW` | Available hold space |
| `GN` | Number of guns |
| `WW` | Scratch: formatted cost |
| `W$` | Scratch: ship condition description |

### Annotated Code

```basic
 1500  REM
```
- Section marker for ship upgrade/gun purchase.

```basic
 1610 I = INT(1000 + FN R(1000 * (TI + 5) / 6)) * (INT(SC / 50) * (DM > 0) + 1)
     : IF CA < I OR FN R(4) THEN 1700
```
- **Ship upgrade cost formula:**
  - `1000 + FN R(1000 * (TI + 5) / 6)` -- Base cost: 1000 plus a random amount scaling with time. At TI=1: 1000 + FN R(1000) = 1000 to 1999. At TI=24: 1000 + FN R(4833) = 1000 to 5832.
  - Multiplied by `(INT(SC / 50) * (DM > 0) + 1)` -- **Damage surcharge.** If ship is damaged (`DM > 0`), multiplied by `SC/50 + 1` (gets more expensive for bigger ships). If undamaged, multiplied by 1 (no surcharge).
- **Offer conditions (BOTH must be false to see the offer):**
  - `CA < I` -- Player cannot afford it. Skips.
  - `FN R(4)` -- Returns 0-3. Non-zero (75% of the time) skips. **Only 1-in-4 chance of being offered.**
- If either condition is true, jump to gun purchase check.

```basic
 1615 W$ = CHR$(15) + CHR$(15) + "damaged_______" + CHR$(15) + CHR$(16) + "fine"
     :WW = I: GOSUB 600
```
- `W$` -- Builds a string containing two options: "damaged" and "fine", with control characters for selecting between them.
- Formats the cost for display.

```basic
 1620  GOSUB 400: PRINT "Do you wish to trade in your ";
     MID$(W$, (DM = 0) * 25 + 1, 25)
     : PRINT "ship for one with 50 more capacity by   paying an additional ";WW$;", ";T$;"? ";
```
- `MID$(W$, (DM = 0) * 25 + 1, 25)` -- If ship is damaged (`DM = 0` is false = 0), starts at position 1 showing "damaged". If undamaged (`DM = 0` is true = 1), starts at position 26 showing "fine".
- Displays the upgrade offer with the cost.

```basic
 1630 CH$ = "YN": GOSUB 100: IF CH% = 1 THEN CA = CA - I:MW = MW + 50
     :SC = SC + 50:DM = 0: GOSUB 300
```
- `CH$ = "YN"`: CH%=1 is Y, CH%=2 is N.
- If Yes: deducts cost, **adds 50 to hold space AND total capacity**, **fully repairs ship** (`DM = 0`). Updates display.

```basic
 1700  REM
```
- Section marker for gun purchase.

```basic
 1710 I = INT(FN R(1000 * (TI + 5) / 6) + 500): IF CA < I OR FN R(3) THEN 1900
```
- **Gun cost formula:** `INT(FN R(1000 * (TI + 5) / 6) + 500)` -- 500 plus a random amount scaling with time. At TI=1: 500-1499. At TI=24: 500-5332.
- **Offer conditions:** Player must afford it AND `FN R(3)` must be 0. **1-in-3 chance of being offered.**

```basic
 1720 WW = I: GOSUB 600: GOSUB 400: PRINT "Do you wish to buy a ship's gun"
     : PRINT "for ";WW$;", ";T$;"? ";:CH$ = "NY": GOSUB 100
     : IF CH% = 1 THEN 1900
```
- Displays the gun offer. `CH$ = "NY"`: CH%=1 is N, CH%=2 is Y.
- If No (CH%=1), skip to opium seizure check.

```basic
 1730  IF MW >= 10 THEN CA = CA - I:GN = GN + 1:MW = MW - 10: GOSUB 300: GOTO 1900
```
- If there is enough hold space (each gun takes 10 units), buy the gun. Deducts cost, adds a gun, reduces hold space by 10.

```basic
 1740  PRINT : PRINT : PRINT "Your ship would be overburdened, ";T$;"!"
     : CALL 2518: GOSUB 94
```
- Not enough hold space. Error message and beep. Falls through to line 1900 (no retry loop -- the offer is lost).

### Notes
- **Ship upgrade probability: 1-in-4** per port visit (when affordable).
- **Gun purchase probability: 1-in-3** per port visit (when affordable).
- Both offers can appear at any port, not just Hong Kong.
- Ship upgrades always add exactly 50 capacity and fully repair the ship.
- Each gun occupies 10 hold units permanently.
- Costs scale with `(TI + 5) / 6`, meaning they increase roughly linearly with time.
- The damage surcharge on ship upgrades means repairing via upgrade is often cheaper than paying for repairs separately -- but only when the offer comes.

---

## SECTION 12: Port Arrival -- Opium Seizure (Lines 1900-1910)

### Purpose
If the player is carrying opium in the ship hold and is not in Hong Kong, there is a small chance that authorities seize the opium and fine the player.

### Variables Used
| Variable | Role |
|----------|------|
| `ST(2,1)` | Ship hold opium quantity (good index 1 = Opium) |
| `LO` | Current port |
| `CA` | Cash |
| `I` | Fine amount |
| `MW` | Available hold space |

### Annotated Code

```basic
 1900  IF ST(2,1) = 0 OR LO = 1 OR FN R(18) THEN 2000
```
- **Skip conditions (any triggers skip):**
  - `ST(2,1) = 0` -- No opium in ship hold.
  - `LO = 1` -- Currently in Hong Kong (opium trade is tolerated there).
  - `FN R(18)` -- Returns 0-17; non-zero (17/18 of the time) skips. **1-in-18 chance (~5.6%) of seizure.**
- All three conditions must be false for seizure to occur.

```basic
 1910 I = FN R(CA / 1.8):WW = I: GOSUB 600: GOSUB 400: CALL 2512
     :X = USR(25) + USR(26): PRINT WW$;", ";T$;"!"
     :MW = MW + ST(2,1):ST(2,1) = 0:CA = CA - I: GOSUB 300: GOSUB 94
```
- `I = FN R(CA / 1.8)` -- **Fine amount:** random 0 to ~55% of cash.
- `GOSUB 600` -- Formats the fine for display.
- `CALL 2512` -- Alarm sound.
- **USR(25): Displays "Bad joss!!"** and **USR(26): Displays "The authorities have confiscated your opium and fined you "**
- `MW = MW + ST(2,1)` -- Returns the opium's hold space.
- `ST(2,1) = 0` -- **All ship hold opium is confiscated.**
- `CA = CA - I` -- Deducts the fine. **Cash can go negative** from this (no floor check).

### Notes
- **Only ship hold opium is affected.** Opium in the warehouse is safe from seizure.
- **Only fires outside Hong Kong.** Opium is not seized in Hong Kong.
- The fine is independent of the amount of opium -- it is based on cash.
- Cash can go negative from the fine. This is not explicitly handled; the player will need to earn or borrow to recover.
- For Roblox: this is a non-interactive event. Display the message, apply the effects, continue.

---

## SECTION 13: Port Arrival -- Cargo Theft from Warehouse (Lines 2000-2030)

### Purpose
If the player has goods stored in the warehouse, there is a very small chance that some are stolen.

### Variables Used
| Variable | Role |
|----------|------|
| `W` | Total warehouse contents |
| `J` | Loop counter (good index 1-4) |
| `ST(1,J)` | Warehouse cargo for good J |
| `WS` | Warehouse space in use |
| `WW` | Scratch: new reduced quantity |

### Annotated Code

```basic
 2000 W = 0: FOR J = 1 TO 4:W = W + ST(1,J): NEXT J
     : IF W = 0 OR FN R(50) THEN 2100
```
- Sums all warehouse cargo into W.
- **Skip conditions:**
  - `W = 0` -- Warehouse is empty.
  - `FN R(50)` -- Returns 0-49; non-zero (49/50) skips. **1-in-50 chance (2%) of theft.**

```basic
 2030  GOSUB 400: CALL 2512:X = USR(25) + USR(27): PRINT T$;"!"
     : FOR J = 1 TO 4:W = ST(1,J):WW = FN R(W / 1.8):WS = WS - W + WW
     :ST(1,J) = WW: NEXT J: GOSUB 300: GOSUB 96
```
- `CALL 2512` -- Alarm sound.
- **USR(25): "Bad joss!!"** and **USR(27): Displays "Thieves have gotten into your warehouse and stolen cargo, "** followed by "Taipan!".
- **For each good in warehouse:**
  - `W = ST(1,J)` -- Current quantity.
  - `WW = FN R(W / 1.8)` -- New quantity: random 0 to `W/1.8 - 1`. On average, reduces to about 28% of original, meaning **~72% is stolen on average**.
  - `WS = WS - W + WW` -- Updates warehouse usage (decreases by amount stolen).
  - `ST(1,J) = WW` -- Sets the new reduced quantity.

### Notes
- **Only warehouse cargo is affected.** Ship hold cargo is safe from theft.
- Theft applies to ALL goods in the warehouse simultaneously, not just one.
- The `FN R(W / 1.8)` formula means each good is independently reduced. Some goods might lose more than others.
- Very rare event (1-in-50 per port visit) but devastating when it hits.
- For Roblox: non-interactive event. Apply the losses, show the message.

---

## SECTION 14: Price Calculation and Price Events (Lines 2100-2450)

### Purpose
Calculates current prices for all four goods at the current port, then checks for dramatic price swings (crashes and booms).

### Variables Used
| Variable | Role |
|----------|------|
| `CP(I)` | Current price for good I at current port |
| `BP%(LO,I)` | Base price for good I at port LO |
| `LI` | Li Yuen protection flag |
| `LI%` | Li Yuen lapse counter (potentially vestigial) |
| `LO` | Current port |
| `I` | Good index (1-4) |
| `J` | Scratch: crash (0) or boom (1) |
| `K` | Scratch: additional price multiplier modifier |
| `CO$(I)` | Commodity name |

### Annotated Code

```basic
 2100  FOR I = 1 TO 4:CP(I) = BP%(LO,I) / 2 * (FN R(3) + 1) * 10 ^ (4 - I): NEXT I
```
- **Price calculation for each good:**
  - `BP%(LO,I) / 2` -- Half the base price for this good at this port.
  - `* (FN R(3) + 1)` -- Multiplied by a random factor of 1, 2, or 3.
  - `* 10 ^ (4 - I)` -- **Commodity scale factor:**
    - I=1 (Opium): x1000
    - I=2 (Silk): x100
    - I=3 (Arms): x10
    - I=4 (General Cargo): x1
  - **Example (Opium at Hong Kong, base=11):** `11/2 * rand(1,2,3) * 1000` = 5500, 11000, or 16500.

```basic
 2310 LI = LI AND FN R(20): IF LI = 0 AND LI% > 0 THEN LI% = LI% + 1
     : IF LI% > 4 THEN LI% = 0
```
- **Li Yuen protection lapse check:**
  - `LI = LI AND FN R(20)` -- If LI is non-zero (protected), `FN R(20)` returns 0-19. If it returns 0, `LI AND 0 = 0` -- **protection lapses. 1-in-20 chance (5%) per port visit.** If FN R(20) is non-zero, `LI AND non-zero` stays truthy.
  - If protection just lapsed AND `LI% > 0`: increment the lapse counter. If it exceeds 4, reset to 0.
  - **`LI%` appears to be vestigial** -- it is incremented but never read elsewhere in the code. Possibly a remnant from the book version.

```basic
 2330  IF LI = 0 AND LO <> 1 AND FN R(4) THEN GOSUB 400
     :X = USR(28): CALL 2521: GOSUB 94
```
- **Li Yuen warning message:** If unprotected (`LI = 0`), not in Hong Kong (`LO <> 1`), and `FN R(4)` is non-zero (3-in-4 chance):
  - **USR(28): Displays "Li Yuen has sent a message: 'Pay up or suffer the consequences!'"** (or similar warning). `CALL 2521` plays the notification sound.
  - This is a narrative warning only -- no mechanical effect.

```basic
 2410  IF FN R(9) THEN 2500
```
- **Price event check.** `FN R(9)` returns 0-8; non-zero (8/9) skips. **1-in-9 chance (~11%) of a dramatic price swing.**

```basic
 2420  GOSUB 400:I = FN R(4) + 1:J = FN R(2):K = FN R(2) * 5
     : PRINT T$;"!!  The price of ";CO$(I)
```
- `I = FN R(4) + 1` -- Random good (1-4).
- `J = FN R(2)` -- 0 = price crash, 1 = price boom.
- `K = FN R(2) * 5` -- 0 or 5 (used as additional multiplier in booms; not directly used in crashes).
- Displays "Taipan!! The price of [good]..."

```basic
 2430  IF J = 0 THEN CP(I) = INT(CP(I) / 5): PRINT "has dropped to ";CP(I);"!!"
     : CALL 2518
```
- **Price crash (J=0):** Price divided by 5. **This is a huge buying opportunity.** Beep sound.

```basic
 2440  IF J = 1 THEN CP(I) = CP(I) * (FN R(5) + 5):WW = CP(I): GOSUB 600
     : PRINT "has risen to ";WW$;"!!": CALL 2518
```
- **Price boom (J=1):** Price multiplied by a random factor of 5 to 9. `FN R(5) + 5` = 5, 6, 7, 8, or 9. **Massive selling opportunity.** The `K` variable from line 2420 is not used here -- it appears to be vestigial.

```basic
 2450  GOSUB 94
```
- Pause for player to read.

### Notes
- **Price crashes and booms are the primary wealth-building mechanism.** A price crash reduces the price to 20% of normal, and a boom multiplies by 5-9x. Buying during a crash and selling during a boom can yield 25-45x returns.
- Price events are random and per-port-visit. There is no way to predict them.
- The `K` variable (`FN R(2) * 5`) is computed but never used -- likely vestigial.
- **Li Yuen protection has a 5% chance of lapsing each port visit.** The player receives no notification when this happens -- they only learn when attacked or when offered protection again.
- The Li Yuen warning message (line 2330) only appears outside Hong Kong and only when unprotected. It serves as a reminder to buy protection.

---

## SECTION 15: Cash Robbery and Main Port Menu (Lines 2500-2528)

### Purpose
Checks for random cash robbery, then displays the main trading menu with market prices and available actions.

### Variables Used
| Variable | Role |
|----------|------|
| `CA` | Cash |
| `I` | Scratch: robbery amount, then net worth |
| `LO` | Current port |
| `CP(I)` | Current prices |
| `CO$(I)` | Commodity names |
| `BA` | Bank balance |
| `DW` | Debt |
| `CE$` | Control code: clear to end of line |

### Annotated Code

```basic
 2500  REM
```
- Section marker.

```basic
 2501  GOSUB 400: IF CA > 25000 AND NOT(FN R(20)) THEN I = FN R(CA / 1.4)
     :WW = I: GOSUB 600:X = USR(25): PRINT "You've been beaten up and robbed of"
     : PRINT WW$;" in cash, ";T$;"!!": CALL 2512:CA = CA - I: GOSUB 300
     : GOSUB 94: VTAB 22: HTAB 1: PRINT CE$
```
- **Cash robbery check:**
  - `CA > 25000` -- Only triggers if cash exceeds 25,000.
  - `NOT(FN R(20))` -- `FN R(20)` returns 0-19; NOT(0)=1. **1-in-20 chance (5%).**
  - `I = FN R(CA / 1.4)` -- Amount stolen: random 0 to ~71% of cash.
  - **USR(25): "Bad joss!!"** Prints robbery message. `CALL 2512` alarm sound.
  - Deducts from cash. Updates display.
  - **Tip for Roblox players:** Keep cash in the bank to avoid robbery!

```basic
 2510  GOSUB 400: PRINT T$;:X = USR(29)
```
- Clears message area. **USR(29): Displays the market header** "Doings for the day, Taipan?" or similar.

```basic
 2515  FOR I = 1 TO 3 STEP 2: PRINT TAB(4); LEFT$(CO$(I),7);": ";CP(I)
     ; TAB(18); LEFT$(CO$(I + 1),7);": ";CP(I + 1): NEXT I
```
- Prints market prices in two columns:
  - Row 1: Opium (I=1) and Silk (I=2)
  - Row 2: Arms (I=3) and General Cargo (I=4)

```basic
 2520 I = CA + BA - DW: VTAB 22: HTAB 1: PRINT CE$
```
- Calculates net worth (`I = CA + BA - DW`). This is used to determine which menu options are available.
- Clears line 22.

```basic
 2522  IF LO <> 1 THEN X = USR(30):CH$ = "BSQ"
```
- **Non-Hong Kong menu:** Only Buy, Sell, Quit (set sail). **USR(30): Displays "Shall I Buy, Sell, or Quit?"**

```basic
 2524  IF LO = 1 AND I < 1E6 THEN X = USR(31) + USR(32):CH$ = "BSQTV"
```
- **Hong Kong menu (net worth < 1 million):** Buy, Sell, Quit, Transfer, Visit (Wu). **USR(31) + USR(32): Displays the Hong Kong menu.** No Retire option.

```basic
 2526  IF LO = 1 AND I >= 1E6 THEN X = USR(31) + USR(33):CH$ = "BSQTVR"
```
- **Hong Kong menu (net worth >= 1 million):** Adds Retire option. **USR(33): Displays the Retire option.** `CH$ = "BSQTVR"` adds R as the 6th choice.

```basic
 2528  GOSUB 100: ON CH% GOTO 2530,2570,2700,2620,2680,2695
```
- Gets player's choice and dispatches:
  - CH%=1 (B): Buy -> line 2530
  - CH%=2 (S): Sell -> line 2570
  - CH%=3 (Q): Quit/Set sail -> line 2700
  - CH%=4 (T): Transfer -> line 2620
  - CH%=5 (V): Visit Wu -> line 2680
  - CH%=6 (R): Retire -> line 2695

### Notes
- **Retirement is only available in Hong Kong when net worth >= 1,000,000.** The "R" option literally does not appear in the valid character set otherwise.
- **The cash robbery happens at the very start of the trading phase,** before the player can do anything. There is no way to avoid it except by keeping cash below 25,000 (or in the bank).
- Net worth = Cash + Bank - Debt. This can be negative.

---

## SECTION 16: Retire and Millionaire Paths (Lines 2695-2699)

### Purpose
Handles the retirement victory sequence and the play-again prompt.

### Variables Used
| Variable | Role |
|----------|------|
| `OK` | Set to 16 to indicate retirement victory |
| `IV$`/`NV$` | Inverse video on/off |

### Annotated Code

```basic
 2695 OK = 16
```
- Sets OK to 16. This value is not checked elsewhere for retirement specifically -- it signals a successful retirement rather than a combat outcome.

```basic
 2696  GOSUB 400: PRINT IV$; TAB(26): PRINT : PRINT " Y o u ' r e    a"; TAB(26)
     : PRINT : PRINT TAB(26): PRINT : PRINT " M I L L I O N A I R E ! "
     : PRINT TAB(26): PRINT NV$: GOSUB 96
```
- Displays the **"You're a MILLIONAIRE!"** victory message in inverse video with dramatic spacing. Pauses for effect.

```basic
 2698 : GOSUB 20000
```
- Calls the **score and game over screen** routine (line 20000). This is the common endpoint for all game endings (retirement, death, bankruptcy refusal).

```basic
 2699  PRINT "Play again? ";:CH$ = "NY": GOSUB 100: ON CH% GOTO 63999: RUN
```
- Asks "Play again?" Y/N.
- `CH$ = "NY"`: CH%=1 is N, CH%=2 is Y.
- `ON CH% GOTO 63999` -- If CH%=1 (No), jumps to line 63999 (program exit). If CH%=2 (Yes), falls through to `RUN` which restarts the entire program.

### Notes
- The millionaire celebration only displays when the player explicitly chooses Retire from Hong Kong with net worth >= 1,000,000.
- All game endings (death, bankruptcy, retirement) pass through line 2698 to show the score screen.
- `RUN` restarts the program from scratch, re-initializing all variables.

---

## SECTION 17: Buy / Sell / Transfer Mechanics (Lines 2530-2634)

### Purpose
Handles the three core trading actions: buying goods, selling goods, and transferring goods between ship and warehouse.

### Sub-section: Buy (Lines 2530-2560)

### Variables Used
| Variable | Role |
|----------|------|
| `CH%` | Selected commodity index (from "OSAG" input) |
| `CO$` | Selected commodity name |
| `CP` | Selected commodity price |
| `CA` | Cash |
| `W` | Quantity to buy |
| `MW` | Available hold space |
| `ST(2,CH%)` | Ship hold cargo for selected good |
| `R1%` | "All" flag |
| `CE$` | Clear to end of line control code |
| `IV$`/`NV$` | Inverse video on/off |

### Annotated Code

```basic
 2530  VTAB 23: HTAB 1: PRINT CE$;"What do you wish me to buy, ";T$;"? "
     ;:CH$ = "OSAG": GOSUB 100:CO$ = CO$(CH%):CP = CP(CH%)
```
- Prompts for commodity selection. `CH$ = "OSAG"`: O=1 (Opium), S=2 (Silk), A=3 (Arms), G=4 (General).
- Stores the selected commodity name and price for use below.

```basic
 2540  VTAB 22: HTAB 1: PRINT CE$,IV$;: HTAB 31: PRINT " You can ";
     : VTAB 23: HTAB 31: PRINT "  afford ";: VTAB 24: HTAB 31: PRINT "         ";
     :W = INT(CA / CP): IF W > 1E9 THEN W = 1E9 - 1
```
- Displays "You can afford [amount]" in inverse video on the right side.
- `W = INT(CA / CP)` -- Calculates maximum affordable quantity.
- **Cap at 1 billion - 1** to prevent overflow.

```basic
 2542  HTAB 36 - LEN(STR$(W)) / 2: PRINT W;NV$;: VTAB 23: HTAB 1
     : PRINT "How much ";CO$;" shall": PRINT "I buy, ";T$;"? "
     ;: GOSUB 150: IF R1% THEN W = INT(CA / CP): IF W > 1E9 THEN W = 1E9 - 1
```
- Prints the affordable amount (centered). Prompts for quantity.
- If "All", sets W to maximum affordable, capped at 1 billion.

```basic
 2550  IF W < 0 OR CA < W * CP THEN CALL 2524: GOTO 2540
```
- **Validation:** Rejects negative quantities or unaffordable amounts. `CALL 2524` plays error beep. Loops back.

```basic
 2560 MW = MW - W:CA = CA - W * CP:ST(2,CH%) = ST(2,CH%) + W
     : GOSUB 300: VTAB 22: HTAB 1: CALL -958: GOTO 2520
```
- **Execute purchase:** Decreases hold space, deducts cash, adds to ship cargo.
- `CALL -958` -- Clears from cursor to end of screen.
- Returns to the main menu (line 2520).

### Sub-section: Sell (Lines 2570-2600)

```basic
 2570  VTAB 23: HTAB 1: PRINT CE$;"What do you wish me to sell, ";T$;"? "
     ;:CH$ = "OSAG": GOSUB 100:CO$ = CO$(CH%):CP = CP(CH%)
```
- Same commodity selection as buy.

```basic
 2580  VTAB 22: HTAB 1: PRINT CE$: PRINT "How much ";CO$;" shall"
     : PRINT "I sell, ";T$;"? ";: GOSUB 150: IF R1% THEN W = ST(2,CH%)
```
- Prompts for quantity. If "All", sets W to entire ship hold quantity of that good.

```basic
 2590  IF W < 0 OR ST(2,CH%) < W THEN CALL 2524: GOTO 2580
```
- **Validation:** Rejects negative or more than player has. Loops back.

```basic
 2600 MW = MW + W:CA = CA + W * CP:ST(2,CH%) = ST(2,CH%) - W
     : GOSUB 300: VTAB 22: HTAB 1: PRINT CE$;: GOTO 2520
```
- **Execute sale:** Increases hold space, adds cash, removes from ship cargo. Returns to menu.

### Sub-section: Transfer (Lines 2620-2634) -- Hong Kong Only

```basic
 2620  REM
```
- Section marker.

```basic
 2622 W = 0: FOR I = 1 TO 2: FOR J = 1 TO 4:W = W + ST(I,J): NEXT J,I
     : IF W = 0 THEN VTAB 22: HTAB 1: PRINT CE$;"You have no cargo, ";T$;"."
     : CALL 2518: GOSUB 94: GOTO 2520
```
- Sums all cargo (warehouse + ship). If total is 0, prints error and returns to menu.

```basic
 2624  FOR J = 1 TO 4: FOR K = 1 TO 2:I = 3 - K: IF ST(I,J) = 0 THEN 2634
```
- **Nested loop:** For each good (J=1-4), for each direction (K=1: ship-to-warehouse, K=2: warehouse-to-ship):
  - `I = 3 - K` -- When K=1: I=2 (source is ship). When K=2: I=1 (source is warehouse).
  - If the source has 0 of this good, skip to next iteration (line 2634).

```basic
 2626  GOSUB 400: PRINT "How much ";CO$(J);" shall I move"
     : PRINT MID$("to the warehouseaboard ship", K * 16 - 15, 16);", ";T$;"? "
     ;: GOSUB 150: IF R1% THEN W = ST(I,J): IF W > (WC - WS) AND K = 1 THEN W = (WC - WS)
```
- Prompts for transfer amount. The direction text is extracted from a concatenated string:
  - K=1: positions 1-16 = "to the warehouse"
  - K=2: positions 17-32 = "aboard ship"
- If "All": sets W to entire source quantity, but caps at warehouse vacancy when moving to warehouse.

```basic
 2627  IF K = 2 THEN 2630
```
- If moving warehouse-to-ship (K=2), skip warehouse capacity checks and jump to general validation.

```basic
 2628  IF W > 0 AND WS = WC THEN PRINT : PRINT : PRINT "Your warehouse is full, ";T$;"!"
     : CALL 2518: GOSUB 94: GOTO 2626
```
- **Warehouse full check** (moving to warehouse). If warehouse is at capacity, error and retry.

```basic
 2629  IF W > (WC - WS) THEN PRINT : PRINT : PRINT "Your warehouse will only hold an"
     : PRINT "additional ";WC - WS;", ";T$;"!";: CALL 2518: GOSUB 94: GOTO 2626
```
- **Warehouse overflow check.** If requested amount exceeds remaining warehouse space, error and retry.

```basic
 2630  IF W > ST(I,J) THEN PRINT : PRINT : PRINT "You have only ";ST(I,J);", ";T$;"."
     : CALL 2518: GOSUB 94: GOTO 2626
```
- **Insufficient stock check.** Applies to both directions.

```basic
 2632 ST(I,J) = ST(I,J) - W:ST(K,J) = ST(K,J) + W
     :MW = MW + SGN(I - K) * W:WS = WS + SGN(I - K) * W: GOSUB 300
```
- **Execute transfer:**
  - Source (`ST(I,J)`) decreases by W. Destination (`ST(K,J)`) increases by W.
  - `SGN(I - K)` -- When K=1 (ship to warehouse): I=2, SGN(2-1)=1, so MW increases (freed hold space) and WS increases (warehouse usage up).
  - When K=2 (warehouse to ship): I=1, SGN(1-2)=-1, so MW decreases (hold space used) and WS decreases (warehouse usage down).
  - This is an elegant single expression handling both directions.

```basic
 2634  NEXT K,J: GOTO 2500
```
- Continues loop through all goods and directions, then returns to the top of the port phase (line 2500, which re-checks for robbery and redisplays the menu).

### Sub-section: Visit Wu (Line 2680) and Bank (Line 2690)

```basic
 2680  REM
 2690  GOSUB 500: GOTO 2500
```
- Visit Wu option calls the bank deposit/withdraw routine (GOSUB 500, lines 510-590), then returns to the port phase. **Note:** Despite the menu saying "Visit Wu", this actually goes to the bank. The Wu visit (debt/borrow) happens automatically on arrival (lines 1310-1450), not from this menu. The "V" option provides bank access.

### Notes
- Buy/sell operations return to line 2520 (menu redisplay). Transfer returns to line 2500 (which may trigger another robbery check -- though this only fires once due to the cash threshold usually being reduced).
- The 1 billion cap on purchases prevents integer overflow issues.
- There is no cost to transfer goods between ship and warehouse.
- The `SGN(I-K)` trick is a compact way to handle bidirectional transfers in one line.

---

## SECTION 18: Departure -- Set Sail and Overload Check (Lines 2700-3030)

### Purpose
When the player chooses "Quit" (set sail), validates the ship is not overloaded, prompts for a destination, and begins the voyage.

### Variables Used
| Variable | Role |
|----------|------|
| `MW` | Available hold space (negative = overloaded) |
| `D` | Destination port index |
| `LO` | Current port |
| `CH%` | Selected destination (1-7) |

### Annotated Code

```basic
 2700  REM
```
- Section marker.

```basic
 2810  IF MW < 0 THEN GOSUB 400: PRINT "You're ship is overloaded, ";T$;"!!"
     : CALL 2518: GOSUB 94: GOTO 2500
```
- **Overload check.** If hold space is negative (more cargo + guns than capacity), the player cannot depart. Sends them back to the port menu. Note the original typo: "You're" should be "Your".

```basic
 3010  GOSUB 400: PRINT T$;", do you wish to go to:"
     : PRINT "1) Hong Kong, 2) Shanghai, 3) Nagasaki, 4) Saigon, 5) Manila, 6) Singapore, or  7) Batavia ? ";
```
- Displays the destination selection menu.

```basic
 3020 CH$ = "1234567": GOSUB 100:D = CH%: IF D = LO THEN PRINT : PRINT
     : PRINT "You're already here, ";T$;".";: CALL 2518: GOSUB 94: GOTO 3010
```
- Gets destination choice (1-7 mapped to CH%=1-7, which conveniently matches port indices).
- `D = CH%` -- Sets destination.
- If destination equals current port, error message and retry.

```basic
 3030 LO = 0: GOSUB 300: GOSUB 400: GOSUB 490
```
- `LO = 0` -- Sets current location to "at sea" (index 0).
- Updates status display. Clears message area. **GOSUB 490 shows the sailing artwork (USR(5)).**
- Falls through to the travel event checks.

### Notes
- The overload check only prevents departure. The player can become overloaded in port (e.g., by buying guns), but must resolve it before leaving.
- Port indices 1-7 directly match the choice numbers, which simplifies the code.
- After line 3030, the code falls through to line 3100 (pirate check).

---

## SECTION 19: Travel Events -- Generic Pirates (Lines 3100-3120)

### Purpose
During travel, checks for a generic pirate encounter. This is the most common combat trigger.

### Variables Used
| Variable | Role |
|----------|------|
| `BP` | Pirate encounter base (7 for guns start, 10 for cash start) |
| `SN` | Number of pirate ships |
| `SC` | Ship capacity |
| `GN` | Number of guns |
| `F1` | Encounter type flag (1 = generic pirates) |

### Annotated Code

```basic
 3100  REM
```
- Section marker.

```basic
 3110  IF FN R(BP) THEN 3200
```
- `FN R(BP)` returns 0 to BP-1. Non-zero skips. **Pirate encounter chance = 1/BP.**
  - Cash start (BP=10): **10% chance** per voyage.
  - Guns start (BP=7): **~14.3% chance** per voyage.
- If no pirates, jump to Li Yuen check.

```basic
 3120 SN = FN R(SC / 10 + GN) + 1: GOSUB 400: CALL 2512
     : PRINT SN;" hostile ship"; MID$("s", (SN = 1) + 1, 1)
     ;" approaching, ";T$;"!!": GOSUB 96:F1 = 1: GOTO 5000
```
- `SN = FN R(SC / 10 + GN) + 1` -- **Number of pirate ships:** 1 to `SC/10 + GN`. Scales with ship size and guns. At game start (SC=60, GN=0): 1-6 ships. Late game (SC=200, GN=5): 1-25 ships.
- `MID$("s", (SN = 1) + 1, 1)` -- Pluralization: if SN=1, `(SN=1)+1 = 2`, MID$ from position 2 gives "" (empty). If SN>1, position 1 gives "s".
- `CALL 2512` -- Alarm sound.
- `F1 = 1` -- **Generic pirates** (used in combat for damage calculations and flee behavior).
- `GOTO 5000` -- Enter combat.

### Notes
- **BP does not change over the course of a game** in the BASIC.txt version. The book version had it decrease, making pirates more common over time. In this version, the increasing fleet size is the main difficulty scaling.
- The fleet size formula `SC/10 + GN` means upgrading your ship and buying guns paradoxically attracts larger pirate fleets.

---

## SECTION 20: Travel Events -- Li Yuen's Pirates (Lines 3200-3230)

### Purpose
Checks for Li Yuen's pirate fleet encounter. More dangerous than generic pirates but can be avoided by purchasing Li Yuen's protection.

### Variables Used
| Variable | Role |
|----------|------|
| `LI` | Li Yuen protection flag |
| `SN` | Number of pirate ships |
| `SC` | Ship capacity |
| `GN` | Guns |
| `F1` | Encounter type (2 = Li Yuen) |

### Annotated Code

```basic
 3200  REM
```
- Section marker.

```basic
 3210  IF FN R(4 + 8 * LI) THEN 3300
```
- `FN R(4 + 8 * LI)` -- Encounter chance depends on protection:
  - **Unprotected (LI=0):** `FN R(4)` = 0-3. Non-zero skips. **1-in-4 chance (25%).**
  - **Protected (LI=1):** `FN R(12)` = 0-11. Non-zero skips. **1-in-12 chance (~8.3%).** Even with protection, encounters can still happen -- but they are friendly.

```basic
 3220  GOSUB 400: PRINT "Li Yuen's pirates, ";T$;"!!": CALL 2521: GOSUB 94
     : IF LI THEN PRINT : PRINT "Good joss!! They let us be!!"
     : CALL 2521: GOSUB 94: GOTO 3300
```
- Announces Li Yuen's fleet.
- **If protected:** "Good joss!! They let us be!!" -- safe passage. Jumps to storm check. No combat.

```basic
 3230 SN = FN R(SC / 5 + GN) + 5: GOSUB 400: PRINT SN;" ships of Li Yuen's pirate"
     : PRINT "fleet, ";T$;"!!": CALL 2512: GOSUB 94:F1 = 2: GOTO 5000
```
- **Unprotected encounter:**
  - `SN = FN R(SC / 5 + GN) + 5` -- **Always at least 5 ships.** Range: 5 to `SC/5 + GN + 4`. Much larger fleets than generic pirates. At game start (SC=60, GN=0): 5-16 ships. Late game (SC=200, GN=5): 5-49 ships.
  - `F1 = 2` -- **Li Yuen's pirates.** This doubles damage in combat and reduces enemy flee rates.
  - `GOTO 5000` -- Enter combat.

### Notes
- **Li Yuen's pirates are significantly more dangerous** than generic pirates: larger fleets, double damage (F1=2), and enemies are less likely to flee.
- Protection is essential for survival, especially in mid-to-late game.
- Even with protection, there is a 1-in-12 chance of encounter each voyage (but it is always a safe pass-through).
- After a friendly pass-through, code continues to storm check (line 3300).

---

## SECTION 21: Travel Events -- Storm (Lines 3300-3350)

### Purpose
Checks for a storm during travel. Storms can sink the ship (game over) or blow the player off course to a random port.

### Variables Used
| Variable | Role |
|----------|------|
| `DM` | Ship damage |
| `SC` | Ship capacity |
| `LO` | Current port (set to random if blown off course) |
| `D` | Destination (changes if blown off course) |
| `OK` | Set to 1 if ship sinks (game over) |

### Annotated Code

```basic
 3300  REM
```
- Section marker.

```basic
 3310  IF FN R(10) THEN 3350
```
- `FN R(10)` returns 0-9. Non-zero skips. **1-in-10 chance (10%) of a storm.**

```basic
 3320  GOSUB 400: PRINT "Storm, ";T$;"!!": CALL 2521: GOSUB 94
     : IF NOT(FN R(30)) THEN PRINT : PRINT "   I think we're going down!!"
     : CALL 2521: GOSUB 94: IF FN R(DM / SC * 3) THEN PRINT : PRINT
     "We're going down, Taipan!!": CALL 2512:OK = 1: GOTO 2698
```
- Storm announced. `CALL 2521` notification sound.
- **Severity check:** `NOT(FN R(30))` = `FN R(30) == 0` = **1-in-30 chance** of a life-threatening storm.
- If severe: "I think we're going down!!" Then:
  - `FN R(DM / SC * 3)` -- Sinking check. This returns 0 to `DM/SC*3 - 1`.
    - **If DM = 0 (undamaged):** `FN R(0)` = 0, which is falsy. **Cannot sink with no damage.**
    - **If DM/SC = 0.5 (50% damaged):** `FN R(1.5)` = `FN R(1)` = always 0. Still safe (barely).
    - **If DM/SC = 0.8 (80% damaged):** `FN R(2.4)` = `FN R(2)` = 0 or 1. **50% chance of sinking.**
    - **If DM/SC >= 1.0:** `FN R(3)` = 0, 1, or 2. **2-in-3 chance of sinking.**
  - If sinking: `OK = 1`, game over. Jumps to score screen.

```basic
 3330  PRINT : PRINT "    We made it!!": CALL 2521: GOSUB 94
     : IF FN R(3) THEN 3350
```
- Survived the storm. "We made it!!"
- `FN R(3)` returns 0-2. Non-zero skips. **1-in-3 chance of being blown off course** (2-in-3 chance of continuing normally).

```basic
 3340 LO = FN R(7) + 1: ON (LO = D) GOTO 3340: GOSUB 400
     : PRINT "We've been blown off course": PRINT "to ";LO$(LO):D = LO: GOSUB 94
```
- `LO = FN R(7) + 1` -- Random port 1-7.
- `ON (LO = D) GOTO 3340` -- If the random port is the same as the intended destination, try again. This loop guarantees the off-course destination is different from where the player was heading.
- `D = LO` -- Updates destination to the new port.
- Announces the off-course destination.

```basic
 3350 LO = D: GOTO 1000
```
- Sets current location to destination (whether original or blown-off-course).
- **GOTO 1000: Returns to the main loop entry.** This begins the arrival sequence at the new port (time advance, interest, events, etc.).

### Notes
- **Storm sequence:** 10% chance of storm -> if storm, 1/30 chance of severity -> if severe, damage-based sink chance -> if survived, 1/3 chance of blown off course.
- **Overall chance of sinking per voyage:** 10% * 1/30 * (damage-dependent) = very low for healthy ships, very high for damaged ones.
- **Blown off course is often beneficial** -- it gives the player an unexpected port visit with potentially favorable prices.
- Post-combat event chaining: After winning combat (OK=1) or fleeing (OK=3), the code jumps here (line 3300), meaning **storms can still happen after pirate battles** on the same voyage.

---

## SECTION 22: Combat -- Initialization and Main Loop (Lines 5000-5190)

### Purpose
Sets up the combat state and runs the main combat loop. Each round: display state, accept player input, execute action, then process enemy fire.

### Variables Used
| Variable | Role |
|----------|------|
| `SN` | Total remaining enemy ships |
| `S0` | Original enemy count (snapshot for flee calculations) |
| `SA` | Enemies waiting to appear on screen |
| `SS` | Enemies currently on screen |
| `AM%(I,0)` | On-screen enemy I max HP (0 = empty slot) |
| `AM%(I,1)` | On-screen enemy I accumulated damage |
| `BT` | Booty value (loot if player wins) |
| `LC` | Last command (0=none, 1=run, 2=fight, 3=throw) |
| `CMD` | Current command selection (read from keyboard during delay) |
| `OK` | Run momentum / combat outcome code |
| `DM` | Ship damage |
| `SC` | Ship capacity |
| `WW` | Scratch: seaworthiness percentage |
| `TI` | Total months elapsed |
| `EC` | Enemy base HP |
| `F1` | Encounter type (1=generic, 2=Li Yuen) |

### Annotated Code

```basic
 5000  REM
```
- Combat entry point.

```basic
 5030 LC = 0:CMD = 0: PRINT FS$;HM$
```
- `LC = 0` -- No last command yet. `CMD = 0` -- No current command queued.
- Clears screen and homes cursor.

```basic
 5050  VTAB 1: HTAB 1: PRINT "      ships attacking, ";T$;"!"
     : VTAB 1: HTAB 32: PRINT CG$;"!": VTAB 2: HTAB 32: PRINT "!"
     : VTAB 3: HTAB 32: PRINT "<::::::::";CS$: VTAB 2: HTAB 37: PRINT "guns"
     : VTAB 1: HTAB 34: PRINT "We have";
```
- Draws the combat HUD header: "[count] ships attacking, Taipan!" on the left, and a gun count display on the right with a border.

```basic
 5060  PRINT "Your orders are to:"
```
- Prints the prompt line for combat orders.

```basic
 5080  FOR I = 0 TO 9:AM%(I,0) = 0:AM%(I,1) = 0: NEXT I
     :SA = SN:S0 = SN:BT = FN R(TI / 4 * 1000 * SN ^ 1.05) + FN R(1000) + 250:SS = 0
```
- **Initializes combat state:**
  - Clears all 10 on-screen enemy slots (indices 0-9).
  - `SA = SN` -- All enemies start waiting to appear.
  - `S0 = SN` -- Snapshot of original count.
  - `BT = FN R(TI / 4 * 1000 * SN ^ 1.05) + FN R(1000) + 250` -- **Booty calculation.** Value scales with time elapsed, number of ships, and randomness. Minimum 250. **SN^1.05 means larger fleets give disproportionately more loot.**
  - `SS = 0` -- No ships on screen yet (they are spawned in the display routine).

```basic
 5090  REM
```
- Main combat loop starts here.

```basic
 5100  GOSUB 5760: GOSUB 5700:LC = CMD: VTAB 12: HTAB 40
     : PRINT MID$("+ ", NOT(SA) + 1, 1)
```
- `GOSUB 5760` -- Updates the ship count and gun count displays.
- `GOSUB 5700` -- **Spawns new enemy ships** into empty on-screen slots (see Section 24).
- `LC = CMD` -- Saves current command as last command (for run momentum tracking).
- Prints "+" if more ships are waiting to appear (`SA > 0`), or " " if all are visible.

```basic
 5160 DM = INT(DM):WW = 100 - INT(DM / SC * 100): IF WW < 0 THEN WW = 0
```
- `DM = INT(DM)` -- **Truncates fractional damage.** DM can accumulate fractionally from the `I/2` term in enemy damage. This truncation happens once per combat round.
- `WW = 100 - INT(DM / SC * 100)` -- **Seaworthiness percentage using TRUNCATION** (no `+0.5`). Note: this differs from the main status screen formula at line 313, which uses **rounding** (`INT(DM / SC * 100 + .5)`). This means the combat display can show a seaworthiness value up to 1% higher than the status screen for the same damage level. Implementors should reproduce both behaviours faithfully rather than unifying them.
- Clamped to 0 minimum (`IF WW < 0 THEN WW = 0`).

```basic
 5162  VTAB 4: PRINT "Current seaworthiness: ";ST$(INT(WW / 20))
     ;" (";WW;"%)": GOSUB 5600: VTAB 4: PRINT CL$
```
- Displays ship status label and percentage. `GOSUB 5600` is the **combat delay with keypress check** (reads player input during the pause). Then clears the line.

```basic
 5165  IF WW = 0 THEN OK = 0: GOTO 5900
```
- **Ship destroyed.** If seaworthiness hits 0%, set `OK = 0` (sunk) and jump to combat outcomes.

```basic
 5175  GOSUB 5600
```
- Another delay with keypress check, giving the player time to queue their command.

```basic
 5180  ON CMD GOTO 5200,5300,5400
```
- Dispatches to the selected action:
  - CMD=1: Run (line 5200)
  - CMD=2: Fight (line 5300)
  - CMD=3: Throw Cargo (line 5400)

```basic
 5190  VTAB 4: PRINT T$;", what shall we do??": CALL 2512
     : GOSUB 5600: ON (CMD = 0) + 1 GOTO 5500,5180
```
- **No command selected.** If the player has not pressed R, F, or T during the delays, displays "what shall we do??" with alarm.
- Another delay with keypress check. If still no command (`CMD = 0`), `(CMD=0)+1 = 1`, goes to line 5500 (enemy fires without player action). If command now entered, `(CMD=0)+1` would be evaluated differently -- jumps to 5180 to process it.

### Notes
- **Real-time input during combat:** The player can queue R/F/T during any delay loop (GOSUB 5600). This means fast players can pre-select their action while combat animations play. For Roblox, allow input during all combat animations.
- **Booty formula:** `FN R(TI/4 * 1000 * SN^1.05) + FN R(1000) + 250`. Larger fleets and more time = higher potential loot. The `^1.05` exponent makes this slightly superlinear in fleet size.
- **DM truncation:** Fractional damage is lost each round. This is a minor rounding effect that slightly favors the player.

---

## SECTION 23: Combat -- Player Actions: Run, Fight, Throw Cargo (Lines 5200-5480)

### Sub-section: Run (Lines 5200-5240)

### Variables Used
| Variable | Role |
|----------|------|
| `OK` | Run momentum value |
| `IK` | Run acceleration increment |
| `LC` | Last command |
| `SN` | Remaining enemies |
| `W` | Scratch: ships that gave up chase |
| `SA` | Enemies waiting to appear |

### Annotated Code

```basic
 5200  REM
```
- Run action.

```basic
 5205  VTAB 4: HTAB 1: PRINT CL$: VTAB 4: PRINT "Aye, we'll run, ";T$;"!"
     : GOSUB 96: VTAB 4: PRINT CL$
```
- Displays "Aye, we'll run, Taipan!" Brief pause. Clears line.

```basic
 5207  IF LC = 1 OR LC = 3 THEN OK = OK + IK:IK = IK + 1
```
- **Run momentum builds if previous action was also Run (LC=1) or Throw (LC=3).** Each consecutive run adds an increasing increment: IK starts at 1, becomes 2, then 3, etc.

```basic
 5208  IF LC = 0 OR LC = 2 THEN OK = 3:IK = 1
```
- **Momentum resets if previous action was nothing (LC=0) or Fight (LC=2).** OK resets to 3, IK resets to 1.

```basic
 5210  IF FN R(OK) > FN R(SN) THEN VTAB 4: PRINT "We got away from 'em, ";T$;"!!"
     : CALL 2518: GOSUB 96: VTAB 4: PRINT CL$:OK = 3: GOTO 5900
```
- **Run success check:** `FN R(OK) > FN R(SN)` -- Random(OK) must exceed Random(SN). Higher OK (more momentum) and fewer enemies (lower SN) make escape more likely.
- If successful: `OK = 3` (fled outcome), jump to combat resolution.

```basic
 5220  VTAB 4: PRINT "Can't lose 'em!!": GOSUB 5600: VTAB 4: PRINT CL$
```
- Run failed. "Can't lose 'em!!" with delay.

```basic
 5230  IF SN > 2 AND FN R(5) = 0 THEN W = FN R(SN / 2) + 1:SN = SN - W:SA = SA - W
     : GOSUB 5680: GOSUB 5750: VTAB 4: PRINT "But we escaped from ";W;" of 'em, ";T$;"!"
     : GOSUB 5600: VTAB 4: PRINT CL$
```
- **Partial escape:** If more than 2 enemies remain AND `FN R(5) = 0` (1-in-5 chance):
  - `W = FN R(SN/2) + 1` -- Lose 1 to `SN/2` pursuers.
  - Removes them from both total and waiting-to-appear counts.
  - `GOSUB 5680` -- Removes ships from the on-screen display if SA went negative.
  - `GOSUB 5750` -- Updates ship count display.

```basic
 5240  GOTO 5500
```
- Proceeds to enemy fire phase.

### Sub-section: Fight (Lines 5300-5390)

### Variables Used
| Variable | Role |
|----------|------|
| `GN` | Number of guns |
| `SN` | Remaining enemies |
| `SK` | Ships sunk this round |
| `K` | Loop counter (gun number) |
| `I` | Scratch: random target slot |
| `AM%(I,0)` | Target HP |
| `AM%(I,1)` | Target accumulated damage |
| `S0` | Original fleet size |
| `F1` | Encounter type |
| `W` | Scratch: ships that fled |

### Annotated Code

```basic
 5300  REM
```
- Fight action.

```basic
 5302  IF GN = 0 THEN VTAB 4: HTAB 1: PRINT "We have no guns, ";T$;"!!"
     : GOSUB 5600: VTAB 4: PRINT CL$: GOTO 5500
```
- No guns: cannot fight. Proceeds to enemy fire.

```basic
 5305  VTAB 4: HTAB 1: PRINT CL$: VTAB 4: PRINT "Aye, we'll fight 'em, ";T$;"!"
     : GOSUB 5600: VTAB 4: PRINT CL$
```
- Fight acknowledged.

```basic
 5310 SK = 0: VTAB 4: PRINT "We're firing on 'em, ";T$;"!"
     : FOR K = 1 TO GN: IF SN = 0 THEN 5340
```
- `SK = 0` -- Reset sunk counter. Each gun fires once (loop 1 to GN). If all enemies already sunk, exit loop early.

```basic
 5320 I = FN R(10): IF AM%(I,0) = 0 THEN 5320
```
- **Target selection:** Pick a random slot (0-9). If that slot is empty (HP = 0), retry. This loops until a valid target is found. **Warning: if no ships are on screen but SN > 0, this could infinite loop.** In practice, GOSUB 5700 ensures ships are spawned before firing.

```basic
 5330  GOSUB 5840:AM%(I,1) = AM%(I,1) + FN R(30) + 10
     : IF AM%(I,1) > AM%(I,0) THEN AM%(I,0) = 0:AM%(I,1) = 0
     : GOSUB 5860: GOSUB 5820:SK = SK + 1:SN = SN - 1:SS = SS - 1
     : GOSUB 5750: IF SS = 0 THEN GOSUB 5700
```
- `GOSUB 5840` -- **Hit animation** (draws an explosion on the target ship).
- `AM%(I,1) = AM%(I,1) + FN R(30) + 10` -- **Damage per shot: random 10 to 39.**
- **Sink check:** If accumulated damage exceeds max HP:
  - `AM%(I,0) = 0:AM%(I,1) = 0` -- Clear the slot.
  - `GOSUB 5860` -- **Sinking animation** (explosion and disappear).
  - `GOSUB 5820` -- **Clear the ship sprite** from display.
  - `SK += 1:SN -= 1:SS -= 1` -- Increment sunk count, decrement totals.
  - `GOSUB 5750` -- Update ship count display.
  - `IF SS = 0 THEN GOSUB 5700` -- If all visible ships sunk, spawn new ones from the waiting pool.

```basic
 5340  NEXT K: IF SK > 0 THEN VTAB 4: HTAB 1: PRINT "Sunk ";SK
     ;" of the buggers, ";T$;"!": CALL 2521: GOSUB 5600: VTAB 4: PRINT CL$
```
- After all guns fire: if any ships sunk, announce with success sound.

```basic
 5350  IF SK = 0 THEN VTAB 4: HTAB 1: PRINT "Hit 'em, but didn't sink 'em, ";T$;"!"
     : GOSUB 5600: VTAB 4: PRINT CL$
```
- If no ships sunk but guns fired, "Hit 'em, but didn't sink 'em!"

```basic
 5360  IF FN R(S0) < SN * .6 / F1 OR SN = 0 OR SN = S0 OR SN < 3 THEN 5500
```
- **Enemy flee check.** Enemies might flee if:
  - `FN R(S0) < SN * 0.6 / F1` -- Random check weighted by how many remain relative to original count. F1=2 for Li Yuen halves the flee chance (Li Yuen's men are braver).
  - But skip if: `SN = 0` (all sunk), `SN = S0` (none sunk yet), or `SN < 3` (too few to flee).
- If none of the flee conditions are met, skip to enemy fire.

```basic
 5362 W = FN R(SN / 3 / F1) + 1:SN = SN - W:SA = SA - W: GOSUB 5680
```
- **Flee count:** `FN R(SN/3/F1) + 1` -- 1 to `SN/3` ships flee (halved for Li Yuen). Remove them.
- `GOSUB 5680` -- Handle display cleanup if SA went negative.

```basic
 5390  VTAB 4: PRINT W;" ran away, ";T$;"!": GOSUB 5750
     : CALL 2521: GOSUB 5600: VTAB 4: PRINT CL$: GOTO 5500
```
- Announce fleeing ships. Proceed to enemy fire.

### Sub-section: Throw Cargo (Lines 5400-5480)

### Variables Used
| Variable | Role |
|----------|------|
| `ST(2,J)` | Ship hold cargo |
| `CH%` | Selected good (or 5 = all) |
| `W` | Quantity to throw |
| `WW` | Total thrown |
| `MW` | Hold space |
| `RF` | Raft factor (vestigial) |
| `OK` | Run momentum (boosted by thrown cargo) |
| `II, IJ, IK` | Loop bounds for throw-all |

### Annotated Code

```basic
 5400  REM
```
- Throw cargo action.

```basic
 5410  GOSUB 400: PRINT "You have the following on board, ";T$;":"
     ;: FOR J = 1 TO 4: VTAB 20 + (J = 3 OR J = 4): HTAB 1 + 19 * (J = 2 OR J = 4)
     : PRINT RIGHT$("         " + LEFT$(CO$(J),7), 9);": ";ST(2,J): NEXT J
```
- Lists all ship cargo in a 2x2 grid.

```basic
 5420  VTAB 4: PRINT "What shall I throw overboard, ";T$;"? "
     ;:CH$ = "OSAG*": GOSUB 100: VTAB 4: HTAB 1: PRINT CL$
```
- Prompts for commodity choice. `CH$ = "OSAG*"`: O=1, S=2, A=3, G=4, *=5 (throw all).

```basic
 5430  IF CH% = 5 THEN II = 1:IJ = 4:IK = 1E9: GOTO 5450
```
- **Throw all ("*"):** Sets loop to cover all goods (1-4), quantity cap at 1 billion. Jumps to the throw execution.

```basic
 5440  VTAB 4: PRINT "How much, ";T$;"? ";: GOSUB 150:II = CH%:IJ = CH%
     : IF R1% THEN W = ST(2,II)
```
- For a single good: gets quantity. If "All", throws entire stock of that good. Sets loop to just that one good (II=IJ=CH%).

```basic
 5450 WW = 0: FOR J = II TO IJ:IK = ST(2,J): IF W > IK THEN W = IK
```
- Caps quantity at what is actually on board for each good.

```basic
 5460 ST(2,J) = ST(2,J) - W:WW = WW + W:MW = MW + W: NEXT J
     : VTAB 4: HTAB 1: PRINT CL$
```
- Removes cargo from ship. Tracks total thrown (WW). Frees hold space.

```basic
 5470  IF WW = 0 THEN VTAB 4: PRINT "There's nothing there, ";T$;"!"
     : CALL 2518: GOSUB 5600: VTAB 4: PRINT CL$
```
- If nothing was thrown (0 of selected good), error message.

```basic
 5480  GOSUB 400: IF WW > 0 THEN RF = RF + WW / 3:OK = OK + WW / 10
     : VTAB 4: PRINT "Let's hope we lose 'em, ";T$;"!": CALL 2521
     : GOSUB 5600: VTAB 4: PRINT CL$: GOTO 5210
```
- **If cargo was thrown:**
  - `RF = RF + WW / 3` -- Accumulates "raft factor". **RF is never read elsewhere in the BASIC listing -- it is vestigial.**
  - `OK = OK + WW / 10` -- **Boosts run momentum** by thrown_amount / 10. This significantly improves the chance of escape.
  - **GOTO 5210: Immediately attempts to run!** Throwing cargo is NOT a standalone action -- it always chains into a run attempt. This is critical for Roblox implementation.

### Notes
- **Throwing cargo + auto-run is the escape strategy.** Throwing large amounts of cargo then automatically running with boosted momentum is the primary way to flee overwhelming fleets.
- The run attempt at line 5210 uses the boosted OK value, so the more cargo thrown, the better the escape chance.
- If the run at 5210 fails, the player returns to normal combat flow (enemy fire at 5500, then back to command selection).
- `RF` (raft factor) is accumulated but never read. It may have been intended for a lifeboat mechanic that was cut.

---

## SECTION 24: Combat -- Enemy Fire (Lines 5500-5560)

### Purpose
After the player's action (or if no action was taken), surviving enemies fire on the player's ship.

### Variables Used
| Variable | Role |
|----------|------|
| `SN` | Remaining enemies |
| `SA` | Enemies waiting to appear |
| `I` | Effective number of shooters (capped at 15) |
| `GN` | Player's guns |
| `DM` | Ship damage |
| `SC` | Ship capacity |
| `ED` | Enemy damage base |
| `F1` | Encounter type (1=generic, 2=Li Yuen) |
| `MW` | Hold space (freed if gun destroyed) |
| `OK` | Set to 2 if Li Yuen intervenes |

### Annotated Code

```basic
 5500  REM
```
- Enemy fire phase.

```basic
 5505  IF SN = 0 THEN VTAB 4: PRINT "We got 'em all, ";T$;"!!"
     : CALL 2521: GOSUB 5600:OK = 1: GOTO 5900
```
- **All enemies sunk.** Victory! `OK = 1`. Jump to combat outcomes.

```basic
 5510  VTAB 4: PRINT "They're firing on us, ";T$;"!": GOSUB 5600
     : VTAB 4: PRINT CL$
```
- Announces enemy fire with delay.

```basic
 5540  FOR I = 1 TO 10: POKE -16298,0: POKE -16299,0: POKE -16297,0: POKE -16300,0
     : FOR J = 1 TO 10: NEXT J,I
```
- **Screen flash / hit effect.** The POKE addresses toggle the Apple II speaker and graphics mode switches rapidly, creating a visual and audio "explosion" effect. The inner loop provides timing.

```basic
 5542  VTAB 4: PRINT "We've been hit, ";T$;"!!": CALL 2512
```
- "We've been hit!" with alarm sound.

```basic
 5545 I = SN: IF I > 15 THEN I = 15
```
- **Caps effective shooters at 15.** Even if 50 ships remain, only 15 contribute to damage. This prevents instant death from massive fleets.

```basic
 5550  IF GN THEN IF FN R(100) < (DM / SC) * 100 OR (DM / SC) * 100 > 80
     THEN I = 1: GOSUB 5600: VTAB 4: PRINT CL$: VTAB 4
     : PRINT "The buggers hit a gun, ";T$;"!!": CALL 2512
     :GN = GN - 1:MW = MW + 10: GOSUB 5600: VTAB 4: PRINT CL$
```
- **Gun destruction check** (only if player has guns):
  - `FN R(100) < (DM/SC) * 100` -- Chance equals current damage percentage. At 50% damage, 50% chance. OR
  - `(DM/SC) * 100 > 80` -- If damage exceeds 80%, **guaranteed** gun hit.
  - If a gun is hit: `I = 1` (reduces effective shooters to 1 for this round's damage), destroys one gun (`GN -= 1`), frees 10 hold units.

```basic
 5555 DM = DM + FN R(ED * I * F1) + I / 2
```
- **Damage dealt to player:**
  - `FN R(ED * I * F1)` -- Random damage: 0 to `ED * shooters * encounter_type - 1`.
    - `ED` starts at 0.5. At ED=0.5, I=15, F1=1 (generic): 0 to 6.
    - At ED=2.0, I=15, F1=2 (Li Yuen): 0 to 59.
  - `+ I / 2` -- Guaranteed minimum damage: half the number of shooters. **This produces fractional values** (e.g., 15/2 = 7.5). DM accumulates fractionally but is truncated at the start of each display loop (line 5160).
- **F1=2 for Li Yuen doubles the random damage component**, making Li Yuen encounters significantly more dangerous.

```basic
 5560  IF NOT(FN R(20)) AND F1 = 1 THEN OK = 2: GOTO 5900
```
- **Li Yuen intervention:** 1-in-20 chance (5%) AND only during generic pirate encounters (F1=1).
- If triggered: `OK = 2` (Li Yuen saved you). Jumps to combat outcomes.

```basic
 5590  GOTO 5090
```
- Loop back to main combat loop for the next round.

### Notes
- **The 15-shooter cap is critical for survival.** Without it, late-game fleets of 30+ ships would destroy the player instantly.
- **Gun hit probability scales with damage.** A vicious cycle: more damage = more likely to lose guns = less ability to fight back = more damage.
- **Li Yuen intervention only helps against generic pirates**, not Li Yuen's own fleet.
- **Damage formula breakdown at game start (ED=0.5, generic pirates, 5 shooters):** `FN R(0.5 * 5 * 1) + 5/2` = `FN R(2.5) + 2.5` = 0-1 + 2.5 = 2.5 to 3.5 damage per round. With SC=60, this is about 4-6% per round.

---

## SECTION 25: Combat -- Display Routines and Ship Management (Lines 5600-5880)

### Purpose
Helper routines for combat: delay with keyboard input checking, ship count display updates, on-screen enemy spawning/clearing, hit animations, and explosion effects.

### Sub-section: Combat Delay with Keypress Check (Lines 5600-5670)

```basic
 5600  VTAB 2: HTAB 21: FOR II = 1 TO T / 3
```
- Starts a delay loop (T/3 = 100 iterations).

```basic
 5610 W = PEEK(-16384): IF W < 128 THEN NEXT II: PRINT : RETURN
```
- Checks keyboard. If no key pressed, continue looping. When loop ends, return.

```basic
 5620  IF W = 210 THEN CMD = 1: PRINT "Run        "
 5630  IF W = 198 THEN CMD = 2: PRINT "Fight      "
 5640  IF W = 212 THEN CMD = 3: PRINT "Throw cargo"
```
- **Key detection:** Apple II key codes (value + 128):
  - 210 = 'R' + 128 -> Run (CMD=1)
  - 198 = 'F' + 128 -> Fight (CMD=2)
  - 212 = 'T' + 128 -> Throw cargo (CMD=3)
- Prints the selected action on screen as feedback.

```basic
 5650  POKE -16368,0: PRINT
 5670  RETURN
```
- Clears keyboard strobe and returns. **The command is now queued in CMD for the main loop to process.**

### Sub-section: Remove Excess On-Screen Ships (Lines 5680-5683)

When ships flee or are destroyed faster than SA is decremented, SA can go negative. This routine removes on-screen ships to compensate.

```basic
 5680  IF SA >= 0 THEN RETURN
```
- If SA is not negative, nothing to do.

```basic
 5681 I = 9: FOR IJ = SA TO -1
```
- Loops from SA (negative) up to -1, removing one on-screen ship per iteration.

```basic
 5682  IF AM%(I,0) = 0 THEN I = I - 1: GOTO 5682
```
- Finds the next occupied slot by scanning downward.

```basic
 5683 AM%(I,0) = 0:AM%(I,1) = 0: GOSUB 5880: GOSUB 5820:I = I - 1:SS = SS - 1: NEXT IJ: RETURN
```
- Clears the slot, computes its screen position (GOSUB 5880), clears the sprite (GOSUB 5820), decrements on-screen count. After all excess removed, returns.

### Sub-section: Spawn Ships into On-Screen Slots (Lines 5700-5740)

```basic
 5700  REM
 5710  FOR I = 0 TO 9: IF AM%(I,0) THEN 5740
```
- Scans all 10 slots. If a slot is occupied (HP > 0), skip it.

```basic
 5720 SA = SA - 1: IF SA < 0 THEN SA = 0: RETURN
```
- Decrement waiting count. If no more ships to spawn, return.

```basic
 5730 AM%(I,0) = FN R(EC) + 20:AM%(I,1) = 0: GOSUB 5800:SS = SS + 1
```
- **Spawn a ship:**
  - `AM%(I,0) = FN R(EC) + 20` -- **Max HP:** random 20 to `EC + 19`. EC starts at 20, so initially 20-39 HP. After year 1: 20-49 HP. After year 2: 20-59 HP. Etc.
  - `AM%(I,1) = 0` -- No damage yet.
  - `GOSUB 5800` -- Draw the ship sprite.
  - `SS += 1` -- Increment on-screen count.

```basic
 5740  NEXT I: RETURN
```
- Continue scanning for empty slots.

### Sub-section: Ship Count / Gun Count Display (Lines 5750-5770)

```basic
 5750  REM
 5760  VTAB 1: HTAB 1: PRINT RIGHT$("    " + STR$(SN), 4)
```
- Prints total enemy ship count, right-aligned in 4 characters.

```basic
 5770  VTAB 2: HTAB 33: PRINT RIGHT$("   " + STR$(GN), 3): RETURN
```
- Prints gun count, right-aligned in 3 characters.

### Sub-section: Ship Sprite Drawing and Clearing (Lines 5800-5880)

```basic
 5800  GOSUB 5880: HTAB X: VTAB Y: PRINT SH$: RETURN
```
- Draws a ship sprite at calculated position. `SH$` is the ship graphic string (defined at line 10250).

```basic
 5820  GOSUB 5880: HTAB X: VTAB Y: PRINT SB$: RETURN
```
- Clears a ship sprite position with blank spaces. `SB$` is the blank sprite (defined at line 10260).

```basic
 5840  GOSUB 5880: POKE 2493,(Y + 4) * 8 - 1: POKE 2494,X - 1
     : FOR J = 0 TO 1:IJ = FN R(6):II = DL%(IJ,J)
     : HTAB X + INT(II / 10): VTAB Y + II - INT(II / 10) * 10
     : PRINT DM$(IJ,J): NEXT J: CALL 2368: RETURN
```
- **Hit animation.** Draws random damage sprites (from `DM$` and `DL%` arrays) at the ship's position. `CALL 2368` triggers a visual effect (likely a screen flash or sound).

```basic
 5860  GOSUB 5880: POKE 2361,(Y + 4) * 8 - 1: POKE 2362,X - 1
     : POKE 2300, FN R(FN R(192)): CALL 2224: RETURN
```
- **Sinking/explosion animation.** Sets up parameters for the machine-language explosion routine at CALL 2224. The random value in POKE 2300 varies the explosion pattern.

```basic
 5880 X = (I - INT(I / 5) * 5) * 8 + 1:Y = INT(I / 5) * 6 + 7: RETURN
```
- **Grid position calculation.** Converts slot index I (0-9) into screen coordinates:
  - `X = (I MOD 5) * 8 + 1` -- 5 columns, 8 characters wide each.
  - `Y = (I DIV 5) * 6 + 7` -- 2 rows, 6 lines tall each, starting at row 7.
  - This creates a **5x2 grid** of enemy ship positions.

### Notes
- The 10-slot display system means at most 10 enemies are visible at a time, even if dozens remain. New ships spawn as visible ones are sunk.
- Enemy HP scales with EC (20 + 10/year), making ships progressively harder to sink.
- The grid layout: slots 0-4 in the top row, slots 5-9 in the bottom row.
- For Roblox: implement the 5x2 grid as UI image elements. Use tweens for hit/sink animations.

---

## SECTION 26: Combat -- Victory/Defeat/Retreat Outcomes (Lines 5900-5940)

### Purpose
Resolves combat outcomes based on the OK flag and chains into post-combat events.

### Variables Used
| Variable | Role |
|----------|------|
| `OK` | Outcome code: 0=sunk, 1=won, 2=Li Yuen saved, 3=fled |
| `BT` | Booty amount (loot from victory) |
| `CA` | Cash |

### Annotated Code

```basic
 5900  GOSUB 200: GOSUB 300: GOSUB 400
```
- Redraws the main screen (GOSUB 200), updates status (GOSUB 300), clears message area (GOSUB 400).

```basic
 5910  IF OK = 0 THEN PRINT "The buggers got us, ";T$;"!!!"
     : PRINT "It's all over, now!!!":OK = 1: GOTO 2698
```
- **Ship destroyed (OK=0).** Game over. Sets OK=1 (reused for a different purpose at the score screen) and jumps to the score/game-over display.

```basic
 5920  IF OK = 1 THEN GOSUB 400: PRINT "We've captured some booty"
     :WW = BT: GOSUB 600: PRINT "It's worth ";WW$;"!": CALL 2518
     :CA = CA + BT: GOSUB 96: GOTO 3300
```
- **Victory (OK=1).** Player captures booty worth BT. Cash increases. **Then jumps to line 3300 -- storm check.** A storm can still occur after winning a battle!

```basic
 5930  IF OK = 2 THEN PRINT "Li Yuen's fleet drove them off!"
     : GOSUB 96: GOTO 3220
```
- **Li Yuen intervention (OK=2).** **Jumps to line 3220 -- the Li Yuen encounter check.** This re-runs the Li Yuen encounter logic, which may result in a safe passage message (if protected) or, rarely, another combat.

```basic
 5940  IF OK = 3 THEN PRINT "We made it, ";T$;"!": CALL 2518
     : GOSUB 96: GOTO 3300
```
- **Fled successfully (OK=3).** **Jumps to line 3300 -- storm check.** A storm can still occur after fleeing.

### Notes
- **Post-combat event chaining is critical:**
  - After victory (OK=1): -> storm check (line 3300)
  - After Li Yuen intervention (OK=2): -> Li Yuen encounter re-check (line 3220) -> possible storm
  - After fleeing (OK=3): -> storm check (line 3300)
  - After death (OK=0): -> game over screen
- This means a single voyage can have: pirates -> combat -> storm -> blown off course. The player is not safe until they actually arrive at a port.
- The Li Yuen re-check after OK=2 is unusual -- it means the player might encounter Li Yuen's own fleet immediately after being saved by Li Yuen. If unprotected, this could trigger another combat.

---

## SECTION 27: Score and Game Over Screen (Lines 20000-20900)

### Purpose
Displays the final score, rating, and summary when the game ends (by any means: retirement, death, or bankruptcy).

### Variables Used
| Variable | Role |
|----------|------|
| `CA` | Cash |
| `BA` | Bank balance |
| `DW` | Debt |
| `TI` | Total months elapsed |
| `SC` | Ship capacity |
| `GN` | Guns |
| `WW` | Scratch: first net worth display, then score |
| `WW$` | Formatted net worth string |

### Annotated Code

```basic
 20000  REM
```
- Score screen entry.

```basic
 20010 WW = CA + BA - DW: GOSUB 600:WW = INT((CA + BA - DW) / 100 / TI ^ 1.1)
```
- First pass: `WW = CA + BA - DW` formats net worth for display via GOSUB 600.
- Second pass: **Score formula: `INT((CA + BA - DW) / 100 / TI ^ 1.1)`**
  - Net worth divided by 100, divided by TI^1.1.
  - **Time penalty:** The `TI^1.1` exponent means taking longer increasingly penalizes the score. A player who reaches 1 million in 12 months scores much higher than one who takes 24 months.
  - Score can be negative if debt exceeds cash + bank.

```basic
 20020  PRINT FS$;HM$;CS$;: PRINT "Your final status:": PRINT
     : PRINT "Net Cash: ";WW$: PRINT
     : PRINT "Ship size: ";SC;" units with ";GN;" guns": PRINT
```
- Displays final status: net cash (formatted), ship size, and guns.

```basic
 20030  PRINT "You traded for "; INT(TI / 12);" year";
     MID$("s", (TI > 11 AND TI < 24) + 1, 1);" and ";TI - INT(TI / 12) * 12
     ;" month"; MID$("s", ((TI - INT(TI / 12) * 12) = 1) + 1, 1)
     : PRINT : PRINT IV$;"Your score is ";WW;".";NV$
```
- Displays trading duration in years and months with correct pluralization.
- Shows the score in inverse video.

```basic
 20040  VTAB 14: PRINT "Your Rating:": PRINT CG$;"[";: & 45,31: PRINT "]"
     : FOR I = 1 TO 5: PRINT "!";: HTAB 33: PRINT "!": NEXT I
     : PRINT "<";: & 58,31: PRINT ">";CS$: VTAB 16
```
- Draws a bordered box for the rating display.

```basic
 20050  HTAB 2: IF WW > 49999 THEN PRINT IV$;
 20060  PRINT "Ma Tsu";NV$;"          50,000 and over "
```
- **Ma Tsu rating:** Score >= 50,000. Highlighted in inverse if achieved.

```basic
 20070  HTAB 2: IF WW < 50000 AND WW > 7999 THEN PRINT IV$;
 20080  PRINT "Master ";T$;NV$;"    8,000 to 49,999"
```
- **Master Taipan rating:** Score 8,000 to 49,999.

```basic
 20090  HTAB 2: IF WW < 8000 AND WW > 999 THEN PRINT IV$;
 20100  PRINT T$;NV$;"          1,000 to  7,999"
```
- **Taipan rating:** Score 1,000 to 7,999.

```basic
 20110  HTAB 2: IF WW < 1000 AND WW > 499 THEN PRINT IV$;
 20120  PRINT "Compradore";NV$;"           500 to    999"
```
- **Compradore rating:** Score 500 to 999.

```basic
 20130  HTAB 2: IF WW < 500 THEN PRINT IV$;
 20140  PRINT "Galley Hand";NV$;"          less than 500"
```
- **Galley Hand rating:** Score below 500.

```basic
 20170  VTAB 11
 20180  IF WW < 99 AND WW >= 0 THEN PRINT "Have you considered a land based job?"
     : PRINT
```
- Humorous jab at very low scores (0-98).

```basic
 20190  IF WW < 0 THEN PRINT "The crew has requested that you stay on shore for their safety!!"
     : PRINT
```
- Insult for negative scores (ended with more debt than assets).

```basic
 20900  VTAB 23: RETURN
```
- Positions cursor and returns to the play-again prompt (line 2699).

### Notes
- **Rating thresholds:** Ma Tsu (50,000+), Master Taipan (8,000-49,999), Taipan (1,000-7,999), Compradore (500-999), Galley Hand (<500).
- The score formula heavily penalizes time. A quick millionaire retirement is the optimal strategy.
- All ratings are displayed, with the achieved one highlighted in inverse video.

---

## SECTION 28: Game Initialization (Lines 10000-10310)

### Purpose
Complete game setup: loads machine-language routines, dimensions arrays, defines the random number function, sets up control codes, handles the title screen, gets the firm name, offers the starting choice, and reads all DATA statements.

### Variables Used (Initialized)
| Variable | Initial Value | Meaning |
|----------|---------------|---------|
| `MO` | 1 | January |
| `YE` | 1860 | Starting year |
| `SC` | 60 (or 10) | Ship capacity |
| `BA` | 0 | Bank balance |
| `LO` | 1 | Starting port (Hong Kong) |
| `TI` | 1 | Months elapsed (starts at 1, not 0) |
| `WC` | 10000 | Warehouse capacity |
| `WS` | 0 | Warehouse usage |
| `DW` | 5000 or 0 | Starting debt |
| `CA` | 400 or 0 | Starting cash |
| `MW` | 60 or 10 | Starting hold space |
| `GN` | 0 or 5 | Starting guns |
| `BP` | 10 or 7 | Pirate encounter base |
| `EC` | 20 | Enemy HP pool |
| `ED` | 0.5 | Enemy damage base |

### Annotated Code

```basic
 10000  REM
```
- Full initialization entry point (jumped to from line 10).

```basic
 10010  CALL 6147: POKE 1013,76: POKE 1014,224: POKE 1015,9: POKE 10,76
     : POKE 11,16: POKE 12,11: POKE 1010,102: POKE 1011,213: POKE 1012,112
     : DIM LO$(7),CO$(4),CP(4),BP%(7,4),ST(2,4),AM%(9,1),DM$(5,1),DL%(5,1),ST$(5)
```
- `CALL 6147` -- **Loads machine-language routines** from disk or memory. This sets up all the USR() functions and CALL addresses used throughout the game.
- The POKE statements set up **jump vectors** for the machine-language routines, configuring the USR function dispatch table and other hooks into the AppleSoft interpreter.
- **Array dimensions:**
  - `LO$(7)` -- Port names (0-7; index 0 = "At sea")
  - `CO$(4)` -- Commodity names (1-4)
  - `CP(4)` -- Current prices (1-4)
  - `BP%(7,4)` -- Base price matrix (port 1-7, good 1-4). Integer array (%) for memory efficiency.
  - `ST(2,4)` -- Cargo storage (1=warehouse, 2=ship; 1-4 goods)
  - `AM%(9,1)` -- On-screen enemy ships (0-9 slots; 0=max HP, 1=damage)
  - `DM$(5,1)` -- Damage animation sprites (6 variants, 2 parts each)
  - `DL%(5,1)` -- Damage animation position offsets
  - `ST$(5)` -- Ship status labels (0-5)

```basic
 10020  DEF FN R(X) = INT(USR(0) * X)
```
- **Defines the random number function.** `USR(0)` calls machine-language routine 0, which returns a random float between 0 and 1. Multiplied by X and truncated gives an integer from 0 to X-1.

```basic
 10040 HM$ = CHR$(16):CS$ = CHR$(1) + "0":CA$ = CHR$(1) + "1"
     :CG$ = CHR$(1) + "2":BD$ = CHR$(2):CD$ = CHR$(3):DD$ = CHR$(4)
     :IV$ = CHR$(9):NV$ = CHR$(14):FS$ = CHR$(25):CE$ = CHR$(6):CL$ = CHR$(5)
```
- **Display control codes.** These are custom control sequences interpreted by the machine-language display routines:
  - `HM$` = CHR$(16): Home cursor
  - `CS$` = CHR$(1)+"0": Color scheme 0 (normal text)
  - `CA$` = CHR$(1)+"1": Color scheme 1 (highlight)
  - `CG$` = CHR$(1)+"2": Color scheme 2 (graphics/border)
  - `BD$` = CHR$(2): Begin sprite definition
  - `CD$` = CHR$(3): Continue sprite definition (next row)
  - `DD$` = CHR$(4): End sprite definition
  - `IV$` = CHR$(9): Inverse video on
  - `NV$` = CHR$(14): Normal video (inverse off)
  - `FS$` = CHR$(25): Full screen clear/reset
  - `CE$` = CHR$(6): Clear to end of line
  - `CL$` = CHR$(5): Clear line

```basic
 10045  IF PEEK(2367) = 236 THEN 10070
```
- Checks if machine-language routines are already loaded (sentinel value). If so, skip the loading animation and go straight to game start.

```basic
 10050  POKE -16368,0
 10060  FOR I = 1 TO 400:CH% = PEEK(-16384):X = USR(0): IF CH% < 128 THEN NEXT
```
- **Loading animation loop.** Calls USR(0) repeatedly (which may also serve to seed the random number generator). Each iteration checks for a keypress. Runs 400 iterations or until a key is pressed.

```basic
 10062  VTAB 20: HTAB 31: PRINT IV$;CA$;"'ESC'";
     : FOR I = 1 TO 20:X = USR(0): IF PEEK(-16384) <> 155 THEN NEXT
     : VTAB 20: HTAB 31: PRINT NV$;CA$ + "'ESC'";
     : FOR I = 1 TO 20:X = USR(0): IF PEEK(-16384) <> 155 THEN NEXT
     : GOTO 10062
```
- **Flashing "ESC" prompt.** Alternates between inverse and normal video, waiting for the player to press ESC (key code 155 = 27 + 128). This serves as the "Press ESC to start" screen while also randomizing the RNG.

```basic
 10070  POKE 2367,236: POKE -16368,0: PRINT NV$;FS$;HM$
```
- Sets the sentinel value (236) so next time we know routines are loaded. Clears keyboard. Resets display.

```basic
 10110  VTAB 8: HTAB 1: PRINT CG$;"[";: & 45,38: PRINT "]";
     : FOR I = 1 TO 8: PRINT "!"; TAB(40);"!";: NEXT I
     : PRINT "<";: & 58,38: PRINT ">";CS$
```
- Draws a large bordered box for the firm name entry screen.

```basic
 10120  VTAB 10: HTAB 7: PRINT CS$;T$;","
     : VTAB 12: HTAB 3: PRINT "What will you name your"
     : VTAB 15: HTAB 13: & 45,22: VTAB 14: HTAB 7: PRINT "Firm: ";CA$;
     : & 32,27: VTAB 14: HTAB 13: POKE 33,39: CALL 2200: POKE 33,40
     :WK$ = MID$(WK$,1): IF WK$ = "" THEN CALL 2521: GOTO 10120
```
- Displays "Taipan, What will you name your Firm:" with an input field.
- `CALL 2200` -- Machine-language string input routine for the firm name.
- `WK$ = MID$(WK$,1)` -- Trims the input string (removes trailing spaces).
- If empty, plays a sound and retries.

```basic
 10130  IF LEN(WK$) > 22 THEN PRINT : VTAB 18
     : PRINT IV$;: & 32,42: PRINT "Please limit your Firm's name to 22     characters or less."
     ;: & 32,59: PRINT NV$: CALL 2518: GOSUB 92: VTAB 18: PRINT CE$: GOTO 10120
```
- **Firm name length check:** Maximum 22 characters. If too long, error message and retry.

```basic
 10140 H$ = WK$: PRINT HM$;CS$: VTAB 6
     : PRINT "Do you want to start . . .": PRINT : PRINT
     : PRINT "  1) With cash (and a debt)": PRINT : PRINT
     : PRINT ,">> or <<": PRINT : PRINT
     : PRINT "  2) With five guns and no cash": PRINT ,"(But no debt!)"
```
- Stores the firm name in H$. Displays the **starting choice:**
  - Option 1: Cash start (400 cash, 5000 debt)
  - Option 2: Guns start (0 cash, 0 debt, 5 guns)

```basic
 10150  PRINT : PRINT : PRINT TAB(10);" ?";:CH$ = "12": GOSUB 100
     :MO = 1:YE = 1860:SC = 60:BA = 0:LO = 1:TI = 1:WC = 10000:WS = 0
```
- Gets the starting choice (1 or 2). Initializes common variables:
  - `MO = 1` -- January
  - `YE = 1860` -- Year 1860
  - `SC = 60` -- Ship capacity 60 (both options start with this; option 2 adjusts via MW)
  - `BA = 0` -- No bank balance
  - `LO = 1` -- Hong Kong
  - **`TI = 1` -- Months elapsed starts at 1, NOT 0.** This is critical for all scaling formulas.
  - `WC = 10000` -- Warehouse capacity
  - `WS = 0` -- Warehouse empty

```basic
 10160  IF CH% = 1 THEN DW = 5000:CA = 400:MW = 60:GN = 0:BP = 10
```
- **Cash start:** 5000 debt, 400 cash, 60 hold space, 0 guns, pirate base 10 (10% encounter rate).

```basic
 10170  IF CH% = 2 THEN DW = 0:CA = 0:MW = 10:GN = 5:BP = 7
```
- **Guns start:** 0 debt, 0 cash, 10 hold space (60 capacity - 5 guns * 10 = 10), 5 guns, pirate base 7 (~14.3% encounter rate).

### Notes on Starting Choice Balance
- **Cash start** gives money to trade immediately but saddles the player with rapidly compounding debt (10%/month). The player must trade aggressively and repay quickly.
- **Guns start** has no debt pressure but only 10 hold space (barely enough to carry cargo) and no cash to buy anything. The player must fight pirates for booty or receive an emergency loan.
- BP=7 (guns start) means more frequent pirate encounters, but with 5 guns the player can fight them.

### Data Statements (Lines 10180-10300)

```basic
 10180  FOR I = 0 TO 7: READ LO$(I): NEXT I
     : DATA At sea,Hong Kong,Shanghai,Nagasaki,Saigon,Manila,Singapore,Batavia
```
- Reads port names. Index 0 = "At sea" (displayed when traveling).

```basic
 10190  FOR I = 1 TO 4: READ CO$(I): FOR J = 1 TO 7: READ BP%(J,I): NEXT J,I
```
- Reads commodity names and base prices. For each commodity, reads the name then 7 base prices (one per port).

```basic
 10200  DATA Opium,11,16,15,14,12,10,13,Silk,11,14,15,16,10,13,12
     ,Arms,12,16,10,11,13,14,15,General Cargo,10,11,12,13,14,15,16
```
- **Base price matrix:**
  - Opium: HK=11, Shanghai=16, Nagasaki=15, Saigon=14, Manila=12, Singapore=10, Batavia=13
  - Silk: HK=11, Shanghai=14, Nagasaki=15, Saigon=16, Manila=10, Singapore=13, Batavia=12
  - Arms: HK=12, Shanghai=16, Nagasaki=10, Saigon=11, Manila=13, Singapore=14, Batavia=15
  - General: HK=10, Shanghai=11, Nagasaki=12, Saigon=13, Manila=14, Singapore=15, Batavia=16
- **Trading tip:** Buy where base price is low, sell where it is high. Singapore has the cheapest Opium (10); Shanghai has the most expensive (16).

```basic
 10210  FOR I = 0 TO 5: READ ST$(I): NEXT I
     : DATA "Critical","  Poor","  Fair","  Good"," Prime","Perfect"
```
- Ship status labels (0=Critical through 5=Perfect).

```basic
 10250 SH$ = BD$ + CG$ + "ABCDEFG" + CD$ + "HIJKLMN" + CD$ + "OIJKLPQ" + CD$
     + "RSTUVWX" + CD$ + "YJJJJJZ" + DD$
```
- **Ship sprite definition.** `BD$` begins the sprite, `CD$` separates rows, `DD$` ends it. The letters are custom character tiles that form the ship graphic. 5 rows of 7 characters.

```basic
 10260 SB$ = BD$: FOR II = 1 TO 5:SB$ = SB$ + "       " + CD$: NEXT II
     :SB$ = SB$ + DD$
```
- **Blank sprite.** Same size as the ship sprite but all spaces. Used to erase ship graphics.

```basic
 10270  FOR I = 0 TO 5: FOR J = 0 TO 1:CH$ = BD$ + CG$
 10280  READ WK$:CH$ = CH$ + WK$: IF RIGHT$(CH$,1) = "*" THEN CH$ = MID$(CH$,1,LEN(CH$) - 1) + CD$: GOTO 10280
 10290 DM$(I,J) = CH$ + DD$: READ DL%(I,J): NEXT J,I
```
- **Damage/hit animation sprites.** Reads 12 sprite definitions (6 pairs). Each sprite is a small graphic shown during combat when a ship is hit. The `*` character in DATA indicates a row continuation. `DL%` stores position offsets for where to draw each damage sprite relative to the ship.

```basic
 10300  DATA cde,20,r,3,fg*,mn,50,tu,23,ij,11,vw,43,0,22,x*,z,63,kl,32,12,14,pq,52,345,34
```
- Raw data for the damage sprites and their position offsets.

```basic
 10310 EC = 20:ED = .5
```
- **Enemy scaling initial values:**
  - `EC = 20` -- Enemy base HP pool. Each enemy gets `FN R(EC) + 20` HP.
  - `ED = 0.5` -- Enemy base damage factor. Used in `FN R(ED * I * F1)`.

```basic
 10990  GOSUB 200: GOTO 1000
```
- Draws the initial main screen (GOSUB 200), then enters the main game loop (GOTO 1000) for the first port arrival at Hong Kong.

### Notes
- `SC = 60` is set for both starting options in line 10150. The guns start effectively has only 10 free hold space because MW is set to 10 (60 - 5 guns * 10 = 10).
- The machine-language loading (CALL 6147 and the POKEs) is entirely platform-specific and irreplaceable in Roblox. All USR() functions must be reimplemented as Lua functions.
- The custom character set (letters in the sprite definitions) maps to graphical tiles in the machine-language display system. For Roblox, use actual ship images/sprites.

---

## SECTION 29: Program Exit (Line 63999)

### Purpose
Cleanly exits the program when the player chooses not to play again.

### Annotated Code

```basic
 63999  PRINT FS$;HM$: TEXT : HOME : POKE 103,1: POKE 104,8: END
```
- `FS$;HM$` -- Clears the custom display.
- `TEXT : HOME` -- Switches to standard text mode and clears the screen.
- `POKE 103,1: POKE 104,8` -- Resets the AppleSoft program pointer, reclaiming memory.
- `END` -- Terminates the program.

### Notes
- For Roblox: return the player to the lobby or show a final screen.

---

## USR() Function Reference

This table summarizes all USR() calls and their inferred purposes based on context:

| USR # | Inferred Purpose | Called At |
|--------|-----------------|-----------|
| USR(0) | Returns random float 0-1 (used in FN R) | Throughout |
| USR(1) | Draws port/ship artwork | Lines 210, 230 |
| USR(2) | Draws additional ship/port graphics | Line 230 |
| USR(3) | Displays port location name in status area | Line 250 |
| USR(4) | Displays port arrival banner | Line 480 |
| USR(5) | Displays sailing/departure artwork | Line 490 |
| USR(6) | Displays "How much will you deposit?" | Line 510 |
| USR(7) | Displays "How much will you withdraw?" | Line 550 |
| USR(8) | Displays ", you have only " (error) | Lines 540, 580 |
| USR(9) | Displays "Arriving at " | Line 1010 |
| USR(10) | Displays "Li Yuen asks " (protection cost) | Line 1060 |
| USR(11) | Displays " in donation. Will you pay?" | Line 1060 |
| USR(12) | Displays ", you do not have enough cash!!" | Lines 1070, 1155 |
| USR(13) | Displays "Do you want Wu to cover the difference?" | Line 1070 |
| USR(14) | Displays "Elder Brother Wu has paid the difference" | Line 1080 |
| USR(15) | Displays "Very well. The deal is off, " | Line 1090 |
| USR(16) | Displays ", do you wish to repair your ship?" | Line 1130 |
| USR(17) | Displays "Your ship is " | Line 1145 |
| USR(18) | Displays "It will cost " (repair) | Line 1145 |
| USR(19) | Displays "How much will you spend on repairs?" | Line 1150 |
| USR(20) | Displays Wu mansion narrative (part 1) | Line 1230 |
| USR(21) | Displays Wu mansion narrative (part 2) | Line 1240 |
| USR(22) | Displays "Do you wish to visit Elder Brother Wu?" | Line 1310 |
| USR(23) | Displays "How much do you wish to repay?" | Line 1370 |
| USR(24) | Displays "How much do you wish to borrow?" | Line 1400 |
| USR(25) | Displays "Bad joss!!" | Lines 1910, 2030, 2501 |
| USR(26) | Displays opium seizure message | Line 1910 |
| USR(27) | Displays warehouse theft message | Line 2030 |
| USR(28) | Displays Li Yuen warning/threat message | Line 2330 |
| USR(29) | Displays market header / "Doings for the day" | Line 2510 |
| USR(30) | Displays non-HK menu "Buy, Sell, or Quit?" | Line 2522 |
| USR(31) | Displays HK menu base options | Lines 2524, 2526 |
| USR(32) | Displays HK menu without Retire | Line 2524 |
| USR(33) | Displays HK menu with Retire | Line 2526 |

---

## CALL Address Reference

| Address | Purpose |
|---------|---------|
| CALL 2200 | String input routine (firm name) |
| CALL 2224 | Explosion/sinking animation |
| CALL 2368 | Hit flash animation |
| CALL 2512 | Alarm/alert sound |
| CALL 2518 | Error/beep sound |
| CALL 2521 | Success/positive sound |
| CALL 2524 | Short error beep |
| CALL 2560 | Character input (from CH$, sets CH%) |
| CALL 2680 | Numeric input (into WK$) |
| CALL 6147 | Load machine-language routines |
| CALL -958 | Clear from cursor to end of screen (AppleSoft ROM) |

---

## Critical Game Balance Numbers Summary

| Parameter | Value | Notes |
|-----------|-------|-------|
| Bank interest | 0.5%/month | Safe, modest growth |
| Debt interest | 10%/month | Doubles every ~7 months |
| Starting debt (cash start) | 5,000 | |
| Starting cash (cash start) | 400 | |
| Starting capacity | 60 (cash) / 10 (guns) | |
| Warehouse capacity | 10,000 | |
| Enemy base HP (EC) | 20, +10/year | |
| Enemy damage base (ED) | 0.5, +0.5/year | |
| Damage per player shot | 10-39 | |
| Max enemies on screen | 10 | |
| Max effective shooters | 15 | |
| Ship upgrade: +50 capacity | 1-in-4 offer chance | |
| Gun: costs 10 hold units | 1-in-3 offer chance | |
| Li Yuen protection lapse | 1-in-20 per port visit | |
| Generic pirate chance | 1/BP (10% or 14.3%) | |
| Li Yuen pirate chance | 1/4 unprotected, 1/12 protected | |
| Storm chance | 1/10 per voyage | |
| Storm severity | 1/30 of storms | |
| Blown off course | 1/3 of survived storms | |
| Price event chance | 1/9 per port visit | |
| Opium seizure | 1/18 (not in HK) | |
| Warehouse theft | 1/50 | |
| Cash robbery | 1/20 (if cash > 25,000) | |
| Wu enforcers | 1/5 (if debt > 20,000) | |
| Score formula | `(CA+BA-DW) / 100 / TI^1.1` | |
| Millionaire threshold | 1,000,000 net worth | |
| Ma Tsu rating | Score >= 50,000 | |
