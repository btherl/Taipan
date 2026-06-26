# Original Apple II Taipan! — Plain System Beep (`CALL 2524`) Catalog

## What the beep is

The original Applesoft game makes all sound by `CALL <addr>` into a machine-language
sound block. There are four consecutive entry points (per
`apple_call_addresses`):

| `CALL` | Hex addr | Sound |
|---|---|---|
| `CALL 2512` | `$9D0` | under_attack (combat) |
| `CALL 2518` | `$9D6` | good_joss |
| `CALL 2521` | `$9D9` | bad_joss |
| `CALL 2524` | `$9DC` | **plain system beep** (the error/rejection beep) |

> **Naming caveat for `2518`/`2521`.** These names follow `sounds.h` (the C port),
> which is also where our project's `goodjoss.wav`/`badjoss.wav` assets come from — so
> our `goodjoss` = `CALL 2518` and our `badjoss` = `CALL 2521`. The independent
> `references/BASIC_ANNOTATED.md` labels them the *opposite* way (it calls `2518`
> "error" and `2521` "positive"). This is only a labeling disagreement — the actual
> event→address mapping is identical in both sources, no events are swapped. Be aware
> of one inherited quirk: the original prints the literal on-screen text **"Good joss!!"**
> while playing `CALL 2521` (BASIC lines 873, 1662–63) — i.e. the tone we call
> `badjoss`. So when wiring `2521`-events into our game, the faithful asset is
> `badjoss` even where the screen says "Good joss!!". None of this affects the beep
> (`CALL 2524`), which is unambiguous.

`sounds.h` only documents the first three. `CALL 2524` is the fourth, undocumented
entry — the plain beep. I identified it as the beep because (a) it is the fourth
consecutive address in the sound block listed in `apple_call_addresses`
(`2524 9dc`), (b) it is the only sound `CALL` not catalogued among
bad/good/under_attack in `sounds.h`, and (c) both of its uses are bare input-rejection
guards that re-prompt the same question (`GOTO` back to the prompt) — the classic
"that input was invalid, try again" beep.

## How I found every occurrence

Searched both source files exhaustively for `CALL 2524`:

- `taipan-applesoft-annotated.txt` → 2 hits (lines **831**, **861**)
- `taipan-applesoft.txt` (raw) → 2 hits (lines **408**, **424**)

The counts match: **the beep is played in exactly 2 places**, both in the
buy/sell trading dialog (BASIC lines 2550 and 2590).

I also enumerated every `CALL` in the raw BASIC: the only sound targets present are
`2512`, `2518`, `2521`, `2524`; the remaining calls (`-958`, `2200`, `2224`, `2368`,
`2560`, `2680`, `6147`) are non-sound ML routines (screen-clear / drawing / RNG /
keyboard input). No other sound entry point is invoked.

## The 2 beep occurrences

Variable key (from the annotated source):
`CA` = cash · `CP` = `CP(CH%)` = current unit price of the selected good ·
`CH%` = selected good index (1=Opium, 2=Silk, 3=Arms, 4=General) ·
`W` = quantity the player entered (or the auto-computed max when they typed **A** = "All", flag `R1%`) ·
`ST(2,CH%)` = quantity of the selected good currently in the **ship hold**
(`ST(1,*)` = warehouse, `ST(2,*)` = ship) · `MW` = free hold space.

### Beep 1 — BUY rejection (BASIC line 2550)

- **Source:** `taipan-applesoft-annotated.txt:830-832` ; raw `taipan-applesoft.txt:407-408`
- **Exact BASIC:**
  ```
  2550  IF W < 0 OR CA < W * CP THEN
          CALL 2524:
          GOTO 2540
  ```
- **Condition (plain English):** Beep if the buy quantity is negative
  (`W < 0`) **OR** the player cannot afford it — cash is less than
  quantity × unit price (`CA < W * CP`).
- **Player action that triggers it:** At the "How much … shall I buy?" prompt
  (port trading dialog, after choosing **B**uy and a good), the player typed a
  negative number, or a quantity that costs more cash than they have. The game
  beeps and `GOTO 2540` re-displays the "You can afford W" prompt to ask again.

### Beep 2 — SELL rejection (BASIC line 2590)

- **Source:** `taipan-applesoft-annotated.txt:860-862` ; raw `taipan-applesoft.txt:423-424`
- **Exact BASIC:**
  ```
  2590  IF W < 0 OR ST(2,CH%) < W THEN
          CALL 2524:
          GOTO 2580
  ```
- **Condition (plain English):** Beep if the sell quantity is negative
  (`W < 0`) **OR** the player is trying to sell more of that good than they
  actually hold on the ship (`ST(2,CH%) < W`).
- **Player action that triggers it:** At the "How much … shall I sell?" prompt
  (after choosing **S**ell and a good), the player typed a negative number, or a
  quantity larger than the amount of that good in the hold. The game beeps and
  `GOTO 2580` re-displays the sell prompt to ask again.

Both beeps share the same shape: a bad numeric quantity at a trading prompt →
`CALL 2524` → loop straight back to re-ask the same question. No state changes.

## "Not a beep" — contrast with the musical rejections

Several over-limit / no-op rejections are NOT the plain beep; they play
**good_joss** (`CALL 2518`) and usually print an explanatory line first. Per
`sounds.h` these include:

- "ship overloaded" (trying to buy/move more than the hold holds)
- "warehouse is full" / "warehouse will only hold an additional …"
- "you have only X in cash" (repaying Wu, depositing in the bank)
- "you have only X in the bank" (withdrawing too much)
- "won't loan you so much" (borrowing from Wu)
- "there's nothing there" (throwing cargo you don't have)
- "you have no cargo" (warehouse transfer with empty hold)
- "you're already here!" (selecting the current port as destination)

Likewise **bad_joss** (`CALL 2521`) and **under_attack** (`CALL 2512`) are reserved
for narrative events (Li Yuen, pirates, storms, combat hits, empty firm-name entry,
etc.). None of those are the plain beep — so the catalog above (lines 2550, 2590) is
the complete list of true `CALL 2524` beeps.

## Step 3 finding — are there any non-`CALL 2524` beep mechanisms?

**No.** I searched the BASIC and the C sources for every alternative beep mechanism:

- `PRINT CHR$(7)` / `CHR$ (7)` — none.
- Monitor bell calls `CALL -198` (`$FF3A` BELL), `CALL -1059`, `CALL 64600` — none.
- An embedded literal ASCII-7 (bell) control byte inside any `PRINT` string — none.
  (The `0x07` hits in the repo are font/glyph and help-message data
  — `characters`, `convfont.c`, `helpmsgs.c`, `help.txt` — not bell control codes.)

So in the original game the **only** plain-beep mechanism is `CALL 2524`, used
exactly twice (buy and sell quantity rejection).

For completeness: the C reimplementation **deliberately removed** these error beeps —
`NOTES.txt:127-128` ("The game doesn't beep at you when you enter something
incorrect. This is a stylistic decision (I hate error beeps). It does play the 'bad
joss' …"). This is expected and confirms the original BASIC, not the C port, is the
authority for beep behavior.
