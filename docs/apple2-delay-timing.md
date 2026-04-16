# Apple II Taipan — Timed Delay Analysis

The original Applesoft BASIC source uses a busy-wait delay routine entered at three
different points (lines 92, 94, 96) to produce pauses of different lengths.
`T = 300` is set at startup.

| Entry point | Iterations | Estimated wall-clock (1 MHz Apple II) | What we implement |
|---|---|---|---|
| GOSUB 92 | 600 (T + T/2 + T/2) | ~6–12 seconds | 10 seconds |
| GOSUB 94 | 300 (T/2 + T/2) | ~3–6 seconds | 5 seconds |
| GOSUB 96 | 150 (T/2) | ~1.5–3 seconds | 2.5 seconds |
| GOSUB 5600 | 100 (T/3) | ~1–2 seconds | 1.5 seconds |

The 92/94/96 routine aborts early if the player presses any key (`PEEK -16384 > 127`).
Line 5600 is a separate combat-specific routine — see below.

---

## GOSUB 92 — Longest delay

Reserved for high-drama scripted moments (only 3 uses in the entire game):

1. Wu sends braves to escort you to his mansion (line 1230)
2. You arrive at the Wu mansion (line 1240)
3. Firm name too long error during startup (line 1638)

---

## GOSUB 94 — Medium delay

The workhorse delay — most narrative beats and all error messages.

**Financial / Wu:**
- Bank deposit confirmation
- Bank withdrawal confirmation
- Debt paid to Wu
- Cancelled Wu transaction
- Wu's warning that braves are coming
- Insufficient funds to repay Wu
- Wu refuses the loan amount requested

**Trading errors:**
- Ship overburden / overloaded
- No cargo to trade
- Warehouse full
- Warehouse capacity exceeded
- Insufficient cargo in warehouse
- Already at destination

**Random events at sea:**
- Opium seized by authorities
- Random event in Li Yuen territory (non-HK, unprotected)
- Price rise announcement
- Beaten up and robbed (cash > 25,000)
- Cutthroat robbery (debt > 20,000)

**Storm sequence (each step):**
- Storm encountered
- "I think we're going down!!"
- "We made it!!" (survived)
- Blown off course

**Pirate encounters:**
- Li Yuen's pirates spotted
- Pirates let you go (allied)
- Li Yuen's fleet attacks

---

## GOSUB 96 — Shortest delay

Quick acknowledgements of positive outcomes and fast-paced combat.

**Navigation / trading:**
- Arrive at a new port (with interest/debt tick)
- Insufficient cash to buy cargo

**Wu:**
- Wu approves the loan ("Good joss!!")

**Events:**
- Cargo seized by customs
- Won the game (millionaire screen)

**Combat sequence:**
- Hostile ships approaching
- Crew agrees to run ("Aye, we'll run!")
- Successfully escaped
- Booty captured from defeated ships
- Li Yuen's fleet drove them off
- Battle victory ("We made it!")

---

## GOSUB 5600 — Combat command input (T/3 = 100 iterations, ~1–2 seconds)

A distinct routine used exclusively inside the combat loop. Unlike 92/94/96, it not
only waits but also **reads and acts on** the keypress:

- Positions cursor at VTAB 2, HTAB 21 (command echo area)
- Loops up to T/3 = 100 iterations reading `PEEK(-16384)`
- If no key within the loop: returns with `CMD` unchanged (game re-prompts)
- If **R** (210) pressed: sets `CMD = 1`, prints "Run        "
- If **F** (198) pressed: sets `CMD = 2`, prints "Fight      "
- If **T** (212) pressed: sets `CMD = 3`, prints "Throw cargo"
- Acknowledges the keystroke (`POKE -16368, 0`) then returns

Called at every combat beat: after displaying seaworthiness, on each fight/run/throw
prompt, after sinking ships, taking hits, losing a gun, throwing cargo, etc.

---

## Pattern

Delay length correlates with drama level:

- **Longest (92):** Scripted cinematic moments — Wu confrontation only.
- **Medium (94):** Most narrative beats and all error/validation messages.
- **Shortest (96):** Routine acknowledgements and fast combat back-and-forth.
- **Combat (5600):** Fastest pure delay, doubles as command reader during combat.

---

## Completeness check

All T-based loops were found by grepping for `TO T` (matching `TO T`, `TO T/2`, `TO T/3`).
The only other `FOR` loops in the file use literal numbers and are not delays:

- **Line 10060** (`FOR I = 1 TO 400`): Title screen PRNG seed loop — spins `USR(0)` until
  the player presses ESC to randomise the RNG before the game starts.
- **Lines 10062–10083** (`FOR I = 1 TO 20`, twice): Flash "ESC" on and off on the title screen.
- All remaining `FOR` loops iterate over game data (ports, goods, cargo, ship grid, etc.)

The four T-based routines (92, 94, 96, 5600) are the complete set of timed delays.
