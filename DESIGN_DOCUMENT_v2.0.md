# Taipan! -- Roblox Single-Player Game Design Document (Version 2.0)

## Change Log

### v2.0 (2026-03-15) — Code Review Corrections

1. **[Critical] Opium seizure and cargo theft targets corrected** — Opium seizure (line 1900) targets **ship hold** opium, not warehouse. Cargo theft (lines 2000-2030) steals from **warehouse**, not ship hold. Warehouse notes updated accordingly.
2. **[Critical] Ship upgrade offer probability corrected** — Was 3-in-4, actually **1-in-4** (line 1610: `FN_R(4)` non-zero skips).
3. **[Critical] Gun purchase offer probability corrected** — Was 2-in-3, actually **1-in-3** (line 1710: `FN_R(3)` non-zero skips).
4. **[Critical] Li Yuen protection cost formula completed** — For TI > 12, the formula includes a `FN_R(CA)` cash component that was previously missing.
5. **[Critical] Throw cargo auto-triggers run** — After throwing cargo, code jumps directly to the run attempt (line 5480 → GOTO 5210). Throwing is not a standalone action.
6. **[Critical] Post-combat event chaining documented** — After combat resolution, the game chains into storm checks (OK=1, OK=3) or Li Yuen encounter re-check (OK=2).
7. **Li Yuen offer conditions** — Now documents both skip conditions: already protected (LI != 0) OR no cash (CA = 0).
8. **`LI%` counter clarification** — Documented as potentially vestigial; increments when protection lapses and LI% > 0.
9. **`RF` (raft) variable** — Documented as potentially vestigial; accumulated from thrown cargo but not read elsewhere in the BASIC listing.
10. **Event arrival ordering** — Full ordered sequence documented matching BASIC line numbers.
11. **TI starts at 1** — Corrected from implicit assumption of 0. First voyage increments to TI=2.
12. **Wu enforcers fire after Wu visit** — Clarified that enforcers (line 1460) follow the Wu encounter block, not as an independent random event.
13. **"A" (All) shortcut** — Applies to ALL numeric inputs throughout the game, not just buying.
14. **Overload prevention** — Negative hold space prevents leaving port (line 2810).
15. **DM (damage) accumulates fractionally within a combat round** — `I/2` in damage formula produces fractional values; `INT(DM)` truncates at the start of each combat display loop.
16. **BigNumber module moved to `shared/`** — Client needs it for display formatting.
17. **`game:BindToClose()` added to save system** — Alongside PlayerRemoving for proper shutdown saving.
18. **StreamingEnabled clarification** — Corrected description of what StreamingEnabled actually does; documented proper approach for per-player 3D scenes.
19. **Mobile input section added** — Touch-friendly sizing requirements and dedicated mobile layout consideration.
20. **ARRIVAL state added** — Non-interactive processing cascade, separate from EVENT (interactive).
21. **BANKRUPTCY state added** — Emergency loan flow as a distinct state.
22. **Variable name reference table** — New appendix mapping BASIC variable names to Lua equivalents.

---

## Table of Contents

1. [Game Overview](#1-game-overview)
2. [Complete Game Mechanics](#2-complete-game-mechanics)
3. [Roblox Architecture](#3-roblox-architecture)
4. [Roblox-specific Considerations](#4-roblox-specific-considerations)
5. [Key Implementation Challenges](#5-key-implementation-challenges)
6. [Appendix A: BASIC Variable Reference](#6-appendix-a-basic-variable-reference)

---

## 1. Game Overview

### What is Taipan?

Taipan! is a trading simulation game set in the South China Sea during the 1860s. Originally written by Art Canfil for the Apple II computer (published 1982 by Mega Micro Computers, later documented in a 1986 Hayden Book Company publication by Canfil, Albrecht, and McClenahan), the game places the player in the role of a "taipan" -- a Western merchant-trader operating out of Hong Kong during the turbulent era of the China Trade.

The name "taipan" comes from the Chinese words *tai* ("great/supreme") and *pan* ("leader/boss"), a title adopted by Western traders operating in the China Seas. The game is loosely inspired by James Clavell's novel *Tai-Pan*.

### Core Premise

The player commands a trading vessel, buying and selling goods across seven ports in East and Southeast Asia. The goal is to accumulate wealth through shrewd trading while managing debt, surviving pirate attacks, weathering storms, and navigating random events. The game operates on a turn-based month-by-month cycle.

### Win/Loss Conditions

- **Win (Retirement):** The player can retire at any time while in Hong Kong. If their net worth (cash + bank - debt) reaches 1,000,000 or more, they achieve "Millionaire" status and can retire with honor. Below that threshold, they can still retire but with a lower score.
- **Loss (Death/Bankruptcy):** The player dies if their ship sinks (0% seaworthiness from combat damage or storms), or if they refuse Elder Brother Wu's emergency loan when completely broke (game over).
- **Score:** Calculated as `INT((cash + bank - debt) / 100 / turns^1.1)`, where `turns` is the total number of months traded (TI, starting at 1). This rewards both wealth and speed.
- **Ratings:**
  - Ma Tsu: 50,000+
  - Master Taipan: 8,000 -- 49,999
  - Taipan: 1,000 -- 7,999
  - Compradore: 500 -- 999
  - Galley Hand: < 500

---

## 2. Complete Game Mechanics

### 2.1 Ports and Travel System

**Seven ports**, each with an index used for price calculations:

| Index | Port       |
|-------|------------|
| 1     | Hong Kong  |
| 2     | Shanghai   |
| 3     | Nagasaki   |
| 4     | Saigon     |
| 5     | Manila     |
| 6     | Singapore  |
| 7     | Batavia    |

**Hong Kong (index 1) is special** -- it is the only port where:
- The player has a warehouse (godown) for storing goods
- Elder Brother Wu operates (lending, debt repayment, emergency loans)
- The player can use the bank (deposit/withdraw)
- The player can retire
- Li Yuen's protection can be purchased (in the book version; the BASIC.txt version handles this differently)

**Travel:** Selecting "Quit" from the trading menu presents a destination choice (1-7). The player cannot select their current port. **The player cannot leave port if the ship is overloaded (MW < 0)** — the game rejects the departure attempt (line 2810). Travel advances time by 1 month. During travel, random encounters (pirates, Li Yuen's fleet, storms) may occur.

### 2.2 Trading System

#### Goods

Four tradeable commodities (the BASIC.txt version simplifies from the book's six):

| Index | Good          | Price Scale |
|-------|---------------|-------------|
| 1     | Opium         | 10^3 (thousands) |
| 2     | Silk          | 10^2 (hundreds)  |
| 3     | Arms          | 10^1 (tens)      |
| 4     | General Cargo | 10^0 (ones)      |

Opium is the most valuable per unit, General Cargo the least. All goods occupy 1 unit of hold space regardless of type.

#### Base Prices Per Port

The game stores a base price matrix `BP%(port, good)` initialized from DATA:

```
             Opium  Silk  Arms  General
Hong Kong:     11    11    12     10
Shanghai:      16    14    16     11
Nagasaki:      15    15    10     12
Saigon:        14    16    11     13
Manila:        12    10    13     14
Singapore:     10    13    14     15
Batavia:       13    12    15     16
```

These base prices drift upward over time: each January (new year), every base price increases by a random amount `FN R(2)` (0 or 1).

#### Price Calculation

Current prices at each port visit are calculated as:

```
CP(i) = BP%(port, i) / 2 * (FN_R(3) + 1) * 10^(4 - i)
```

Where `FN_R(n)` returns a random integer from 0 to n-1. This means:
- The base price is halved, then multiplied by a random factor of 1, 2, or 3
- Then scaled by the commodity's order of magnitude (Opium x1000, Silk x100, Arms x10, General x1)

**Example:** Opium at Hong Kong with base 11: `11/2 * rand(1-3) * 1000` = range of 5,000 to 16,500.

#### Price Events (Bears and Bulls)

There is roughly a 1-in-9 chance each port visit of a dramatic price swing:

```
if FN_R(9) == 0:
    i = random good (1-4)
    j = FN_R(2)  -- 0 = crash, 1 = boom
    if crash: price = price / 5
    if boom:  price = price * (FN_R(5) + 5)  -- multiply by 5-9x
```

These events are announced ("The price of Opium has dropped to 1200!!") and represent the core profit opportunity of the game. Buying low during a crash and selling high during a boom is the primary wealth-building strategy.

#### Buy/Sell Mechanics

- **Buy:** Player selects a good, sees how many they can afford (`INT(cash / price)`), enters a quantity. Entering **"A" (All)** buys the maximum affordable amount. The purchase reduces cash and hold space, and adds to ship cargo.
- **Sell:** Player selects a good, enters a quantity (up to the amount on board). Entering **"A" (All)** sells the entire amount on board.
- **"A" (All) shortcut:** The "A" input is handled by the generic numeric input routine (line 150, `R1%` flag) and works on ALL numeric inputs throughout the game — buying, selling, transferring, depositing, withdrawing, repaying debt, borrowing, and repairing.
- Capped at 1 billion units per transaction.

### 2.3 Warehouse (Godown) System

- Located only in Hong Kong
- Maximum capacity: 10,000 units (variable `WC`)
- Player can transfer goods between ship and warehouse in either direction
- **Warehouse contents are safe from opium seizure and storms/combat, but NOT from cargo theft** (see section 2.5). Cargo theft specifically targets warehouse goods.
- Warehouse contents persist across voyages
- Moving goods to warehouse frees hold space; moving to ship consumes it
- Current warehouse usage tracked by `WS`

### 2.4 Ship System

**Starting choice:**
1. **Cash start:** 400 cash, 5000 debt to Wu, 60 hold capacity, 0 guns, pirate encounter chance BP=10
2. **Guns start:** 0 cash, 0 debt, 10 hold capacity, 5 guns, pirate encounter chance BP=7

**Ship attributes:**
- `SC` -- Ship total capacity (starts at 60 or 10 depending on choice)
- `MW` -- Available hold space (= SC minus goods aboard minus guns*10)
- `GN` -- Number of guns (each gun takes 10 hold units)
- `DM` -- Damage points accumulated. **DM can accumulate fractionally** within a combat round (the `I/2` term in the enemy damage formula produces non-integer values). However, `DM` is truncated via `INT(DM)` at the start of each combat display loop iteration (line 5160). This means fractional damage is lost each round — a minor but real rounding effect.
- Ship status: `100 - INT(DM/SC * 100)`, displayed as a percentage
- Status labels: Critical (0-19%), Poor (20-39%), Fair (40-59%), Good (60-79%), Prime (80-99%), Perfect (100%)

**Ship upgrades:** Offered periodically when in port with sufficient cash:
```
cost = INT(1000 + FN_R(1000 * (turns + 5) / 6)) * (INT(SC/50) * (damaged) + 1)
```
- Adds 50 capacity and repairs all damage
- Requires: cash >= cost AND **1-in-4 chance of being offered** (line 1610: `FN_R(4)` returns 0 one-quarter of the time; non-zero skips the offer)
- Cost scales with time played and ship size

**Gun purchases:** Offered periodically:
```
cost = INT(FN_R(1000 * (turns + 5) / 6) + 500)
```
- Each gun costs 10 hold units
- Requires: cash >= cost AND MW >= 10 AND **1-in-3 chance of being offered** (line 1710: `FN_R(3)` returns 0 one-third of the time; non-zero skips the offer)

### 2.5 Financial System

#### Cash
- Primary liquid currency, used for all transactions
- Can be deposited in or withdrawn from the bank (Hong Kong only)
- Can be stolen by random mugging events

#### Bank
- Available only in Hong Kong
- Earns 0.5% interest per month (`BA = INT(BA + BA * 0.005)`)
- No risk of loss -- bank funds are completely safe
- Useful for protecting large sums from robbery and for passive income

#### Debt to Elder Brother Wu
- Starting debt: 5,000 (cash start) or 0 (guns start)
- **Debt compounds at 10% per month** (`DW = INT(DW + DW * 0.1)`) -- this is extremely aggressive
- Can be repaid at Hong Kong using cash
- Additional borrowing available at Hong Kong (up to 2x current cash)
- Borrowed amount goes to cash; debt increases by the same amount

#### Emergency Loans (Bankruptcy)
When the player is completely broke (no cash, no bank, no cargo on ship or in warehouse, no guns):
```
loan_amount = INT(FN_R(1500) + 500)
repayment = FN_R(2000) * bankruptcy_count + 1500
```
- `bankruptcy_count` (`BL%`) increments each time this happens
- Refusing the loan when broke ends the game
- The repayment amount is always significantly more than the loan -- predatory lending

#### Wu's Enforcers
**Note:** Wu's enforcers fire **after the Wu visit/debt/borrow sequence** (line 1460, following the Wu encounter block starting at line 1310), not as an independent random port event.

If debt exceeds 20,000 and a 1-in-5 bad luck roll (`NOT FN_R(5)`):
- 1-3 bodyguards killed
- All cash stolen
- Debt remains unchanged

**Wu's Warning (separate event):**
If debt exceeds 10,000 while in Hong Kong, AND `WN` flag is not set, AND `D != 0` (not the initial port arrival):
- Wu sends 50-149 braves to escort the player to his mansion (narrative event, forced)
- This is a warning/intimidation event
- Sets `WN = 1` so it only happens once

#### Li Yuen's Protection (BASIC.txt version)
- `LI` flag tracks whether the player has Li Yuen's protection
- Protection can be purchased when offered in Hong Kong
- **Offer conditions:** Skipped if already protected (`LI != 0`) OR if player has no cash (`CA = 0`) — both conditions must be false for the offer to appear (line 1040)
- Cost formula:
  - When `TI <= 12`: `FN_R(CA / 1.8)`
  - When `TI > 12`: **`FN_R(CA) + FN_R(1000 * TI) + 1000 * TI`** — note the `FN_R(CA)` component based on the player's cash. This is derived from lines 1050-1060: when TI > 12, `W` is set to 1 (instead of 1.8), so the final cost becomes `FN_R(CA / 1) + FN_R(1000*TI) + 1000*TI`.
- Protection randomly expires: `LI = LI AND FN_R(20)` each port visit (1-in-20 chance of lapsing)
- With protection, Li Yuen's pirates let you pass safely

**`LI%` Counter (potentially vestigial):**
- The `LI%` variable increments when protection has lapsed (`LI = 0`) AND `LI% > 0` (line 2310)
- When `LI%` exceeds 4, it resets to 0
- `LI%` is not clearly read or acted upon elsewhere in the BASIC listing — it may be vestigial from the book version or from a feature that was cut

#### Mugging / Seizure Events

1. **Opium seizure** (line 1900 — when **ship hold** has opium `ST(2,1) != 0`, not in Hong Kong `LO != 1`, 1-in-18 chance):
   - Confiscates all opium from **ship hold** (`ST(2,1) = 0`)
   - Costs `FN_R(CA / 1.8)` in cash (bribes/fines)
   - **Note:** Opium in the warehouse is NOT affected by seizure

2. **Cargo theft** (lines 2000-2030 — when **warehouse** has goods `ST(1,J) total != 0`, 1-in-50 chance):
   - Each good in **warehouse** reduced to `FN_R(amount / 1.8)` -- lose roughly 44% on average
   - **Note:** Ship hold cargo is NOT affected by cargo theft

3. **Cash robbery** (when cash > 25,000, 1-in-20 chance):
   - Lose `FN_R(CA / 1.4)` cash -- up to ~71% of cash

### 2.6 Combat System

#### Encounter Triggers

During travel, encounters are checked in order:

1. **Generic pirates:** Chance = `1 / BP` (BP starts at 7 or 10, meaning ~10-14% base chance)
   - Ship count: `FN_R(SC/10 + GN) + 1`
   - BP value is not explicitly shown to decrease in the BASIC.txt code, but the book version has it decrease over time

2. **Li Yuen's pirates:** Chance varies based on protection status
   - Without protection: `1 / (4 + 8*LI)` where LI=0, so 1-in-4
   - With protection: `1 / (4 + 8*1)` = 1-in-12, and if encountered, they let you pass ("Good joss!!")
   - Ship count: `FN_R(SC/5 + GN) + 5` (always 5+ ships, much more dangerous)

3. **Storms:** 1-in-10 chance (checked after pirates)

#### Combat Flow

Combat is real-time-input turn-based. Each round:

1. Display: ship count, gun count, seaworthiness percentage
2. Player chooses: **Run**, **Fight**, or **Throw Cargo**
3. Player action resolves
4. If enemies remain, they fire back
5. Repeat

**Running:**
- Success chance: `FN_R(OK) > FN_R(SN)` where OK is a running momentum variable
- If previous action was also Run or Throw (LC=1 or LC=3): `OK += IK; IK += 1` (momentum builds)
- If previous action was Fight or first round (LC=0 or LC=2): `OK = 3; IK = 1` (momentum resets)
- If run fails but ship count > 2: 1-in-5 chance of losing `FN_R(SN/2) + 1` pursuers anyway

**Fighting:**
- Each gun fires once per round
- Each shot targets a random on-screen enemy ship
- Damage per shot: `FN_R(30) + 10` (range 10-39)
- Each enemy has HP = `FN_R(EC) + 20` where EC starts at 20 and increases by 10 each January
- When an enemy's accumulated damage exceeds its HP, it sinks
- After firing, if enough ships sunk relative to original count, some may flee:
  - Condition: `FN_R(S0) < SN * 0.6 / F1` (F1=1 for generic, F1=2 for Li Yuen -- Li Yuen's flee less)
  - Additional conditions: SN > 0, SN != S0, SN >= 3
  - Flee count: `FN_R(SN / 3 / F1) + 1`

**Throwing Cargo:**
- Player selects a good (or "*" for all) and quantity to jettison
- Thrown cargo is lost permanently
- Provides run bonus: `OK += thrown_amount / 10`
- Also accumulates a "raft" factor: `RF += thrown_amount / 3` — **`RF` is not read elsewhere in the BASIC listing and may be vestigial** from the book version
- **After throwing cargo, the game immediately attempts to run** (line 5480: `GOTO 5210`). Throwing cargo is NOT a separate standalone action — it always chains into a run attempt. The thrown cargo boosts run momentum before the attempt resolves.

**Enemy Fire:**
- Enemies fire once per round (collectively)
- Number of effective shooters capped at 15
- Chance of hitting a gun: if `FN_R(100) < (DM/SC)*100` OR `(DM/SC)*100 > 80`, one gun is destroyed (freeing 10 hold units)
- Damage dealt: `DM += FN_R(ED * shooters * F1) + shooters/2`
  - `ED` starts at 0.5, increases by 0.5 each January
  - `F1` = 1 for generic pirates, 2 for Li Yuen's (double damage)
  - The `shooters/2` term can produce fractional values; DM is truncated via `INT(DM)` at the start of each display loop
- 1-in-20 chance Li Yuen's fleet intervenes to drive off generic pirates (only if F1=1)

**Combat Outcomes and Post-Combat Event Chaining:**
- **All enemies sunk (OK=1):** Player captures booty worth `BT = FN_R(TI/4 * 1000 * SN^1.05) + FN_R(1000) + 250`. **Then jumps to line 3300 — storm check can still trigger after winning combat.**
- **Li Yuen intervention (OK=2):** **Jumps to line 3220 — Li Yuen encounter is re-checked** (may trigger another Li Yuen encounter or pass through to storm check).
- **Player fled (OK=3):** **Jumps to line 3300 — storm check can still trigger after fleeing.**
- **Ship destroyed (0% seaworthiness):** Game over.

This post-combat chaining means that even after winning a pirate battle or successfully fleeing, the player can still encounter a storm on the same voyage. And after Li Yuen's fleet intervenes, the Li Yuen encounter logic runs again (which may result in a safe passage message or, rarely, another combat).

#### On-Screen Enemy Display

The BASIC.txt version displays up to 10 enemy ships on screen in a 5x2 grid. Each has independent HP. When more than 10 enemies exist, new ships are spawned into empty slots as visible ones are sunk. The variable `SA` tracks how many enemies still need to appear, and `SS` tracks how many are currently on screen.

### 2.7 Storm System

During travel (after pirate checks), 1-in-10 chance of a storm:

1. Storm announced
2. 1-in-30 chance of "going down" check:
   - Sink chance: `FN_R(DM / SC * 3)` -- higher damage = higher sink chance
   - If sunk: game over
3. If survived the severity check: "We made it!!"
4. 2-in-3 chance of being blown off course:
   - New destination = random port (not the intended destination)
   - Announced: "We've been blown off course to [port]"

### 2.8 Ship Repair

Available only in Hong Kong when ship is damaged (`DM > 0`):

```
repair_cost_per_unit = INT((FN_R(60 * (turns+3)/4) + 25 * (turns+3)/4) * SC / 50)
```

- Player is shown damage percentage and full repair cost
- Can pay for partial repair (any amount). "A" (All) pays for full repair (capped by available cash).
- Damage repaired = `INT(amount_paid / cost_per_unit)`
- Cost scales with ship size and game progression

### 2.9 Time System

- Game starts: January 1860
- **`TI` (total months elapsed) starts at 1** (line 10150), not 0. The first voyage increments TI to 2. This means all formulas referencing TI (score, costs, difficulty scaling) are offset by 1 from what a zero-indexed assumption would produce.
- Each voyage (port-to-port) = 1 month
- Month increments each voyage; after December, year advances
- Each January:
  - `EC += 10` (enemy HP pool increases)
  - `ED += 0.5` (enemy damage increases)
  - All base prices `BP%(port, good)` increase by 0 or 1 randomly
- The `TI` variable counts total months elapsed (used in difficulty scaling, score calculation, and various cost formulas)

### 2.10 Event Arrival Ordering

When arriving at a port, events are checked in a specific order matching the BASIC source line sequence. This ordering is critical for faithful reimplementation.

**Full arrival sequence (matching BASIC line numbers):**

| Order | BASIC Lines | Event | Interactive? | Notes |
|-------|-------------|-------|--------------|-------|
| 1 | 1010 | Time advance, interest, debt compound | No | Always runs on arrival |
| 2 | 1020 | January checks (EC, ED, base price drift) | No | Only if month > 12 |
| 3 | 1040-1100 | Li Yuen protection offer | Yes | Hong Kong only; skipped if LI != 0 or CA = 0 |
| 4 | 1120-1160 | Ship repair offer | Yes | Hong Kong only; skipped if DM = 0 |
| 5 | 1210-1240 | Wu warning (braves escort) | No (narrative) | Hong Kong only; if DW >= 10000 and !WN and D != 0 |
| 6 | 1310-1350 | Wu visit (debt repay / borrow / bankruptcy) | Yes | Hong Kong only |
| 7 | 1460 | Wu enforcers | No (narrative) | Fires after Wu visit if DW > 20000 and FN_R(5) = 0 |
| 8 | 1610-1630 | Ship upgrade offer | Yes | Any port; 1-in-4 chance if affordable |
| 9 | 1710-1740 | Gun purchase offer | Yes | Any port; 1-in-3 chance if affordable |
| 10 | 1900-1910 | Opium seizure | No | Ship hold opium seized; not in HK; 1-in-18 |
| 11 | 2000-2030 | Cargo theft | No | Warehouse goods stolen; 1-in-50 |
| 12 | 2100 | Price calculation | No | Always runs |
| 13 | 2310 | Li Yuen protection lapse check | No | 1-in-20 chance protection expires |
| 14 | 2330 | Li Yuen warning message | No | If unprotected and not in HK |
| 15 | 2410-2450 | Price events (crash/boom) | No | 1-in-9 chance |
| 16 | 2500-2501 | Cash robbery | No | If cash > 25000, 1-in-20 |
| — | 2510+ | Player gains control (trading menu) | Yes | — |

### 2.11 Random Event Summary Table

| Event | Trigger | Chance | Location | Target |
|-------|---------|--------|----------|--------|
| Generic pirates | During travel | ~1/BP (7-14%) | At sea | — |
| Li Yuen's fleet | During travel | 1/4 (unprotected) or 1/12 (protected) | At sea | — |
| Storm | During travel | 1/10 | At sea | — |
| Blown off course | During storm | 2/3 (if survived) | At sea | — |
| Ship sinking in storm | During storm | DM/SC * 3 based | At sea | — |
| Price crash/boom | Arriving at port | 1/9 | Any port | — |
| Opium seizure | Arriving at port | 1/18 (if **ship hold** has opium) | Not Hong Kong | Ship hold opium |
| Cash robbery | At port | 1/20 (if cash > 25,000) | Any port | Cash |
| Cargo theft | At port | 1/50 (if **warehouse** has cargo) | Any port | Warehouse goods |
| Wu's enforcers | After Wu visit | 1/5 (if debt > 20,000) | Hong Kong | Cash / bodyguards |
| Ship upgrade offer | At port | **1/4** (if affordable) | Any port | — |
| Gun purchase offer | At port | **1/3** (if affordable) | Any port | — |
| Li Yuen protection offer | Arriving Hong Kong | If LI = 0 AND CA > 0 | Hong Kong | — |

### 2.12 Game Progression and Difficulty Scaling

The game becomes progressively harder and more expensive over time through several mechanisms:

1. **Debt compounds at 10%/month** -- unpaid debt grows exponentially
2. **Enemy HP increases** -- `EC` grows by 10 each year (starts 20, so year 2 = 30, etc.)
3. **Enemy damage increases** -- `ED` grows by 0.5 each year
4. **Ship upgrade costs scale** with `(turns + 5) / 6`
5. **Gun costs scale** similarly
6. **Pirate fleet sizes scale** with ship capacity (`SC/10 + GN` for generic, `SC/5 + GN` for Li Yuen)
7. **Base prices drift upward** -- goods become more expensive to buy, but also sell for more
8. **Score penalizes time** -- denominator includes `TI^1.1`, so taking longer reduces score
9. **Li Yuen protection cost escalates sharply after month 12** — the `FN_R(CA) + FN_R(1000*TI) + 1000*TI` formula means late-game protection can cost most of the player's cash plus a large time-scaled component

The optimal strategy involves aggressive early trading (exploiting price swings), minimal debt, banking profits, and knowing when to retire.

---

## 3. Roblox Architecture

### 3.1 Server vs Client Responsibilities

#### Server (ServerScriptService)

All game-state-altering logic MUST run on the server to prevent exploitation:

- **GameStateManager** -- Authoritative game state: cash, bank, debt, cargo, warehouse, ship stats, current port, date, turn count
- **TradingEngine** -- Price calculation, buy/sell validation, warehouse transfers
- **CombatEngine** -- Pirate encounter generation, damage calculation, combat resolution
- **EventEngine** -- Random event rolls, storm generation, mugging, price events
- **NavigationEngine** -- Travel validation, voyage processing, time advancement
- **FinanceEngine** -- Bank interest, debt compounding, Wu's loans, repair costs
- **ScoreEngine** -- Final score calculation and rating
- **DataPersistence** -- Save/load via DataStoreService

#### Client (StarterPlayerScripts / StarterGui)

The client is purely presentational and input-driven:

- **UIController** -- Manages all screen states and transitions
- **InputHandler** -- Captures player choices and sends RemoteEvent/RemoteFunction calls to server
- **AnimationController** -- Ship sailing animations, combat visuals, weather effects
- **SoundController** -- Ambient port sounds, combat sounds, storm audio
- **CameraController** -- Camera positioning for different game states (port view, sea view, combat view)

#### Shared (ReplicatedStorage)

- **GameConfig** -- Constants: port names, good names, base price matrix, status labels, rating thresholds
- **Types** -- Type definitions for game state, combat state, etc.
- **Enums** -- GamePhase, CombatAction, EventType, etc.
- **Validators** -- Shared validation logic (e.g., can-afford checks)
- **BigNumber** -- Large number formatting utility (needed by both server for data processing and client for display)

### 3.2 Data Structures

```lua
-- ReplicatedStorage/Types.lua

export type PortId = number -- 1-7

export type GameState = {
    playerName: string,
    firmName: string,

    -- Financial
    cash: number,
    bank: number,
    debt: number,

    -- Ship
    shipCapacity: number,     -- SC: total capacity
    guns: number,             -- GN: number of guns
    damage: number,           -- DM: accumulated damage points

    -- Cargo (ship hold)
    shipCargo: { [number]: number },  -- index 1-4, quantity of each good

    -- Warehouse (Hong Kong only)
    warehouseUsed: number,    -- WS
    warehouseCapacity: number, -- WC (10,000)
    warehouseCargo: { [number]: number }, -- index 1-4

    -- Location / Time
    currentPort: PortId,
    month: number,            -- 1-12
    year: number,             -- starts 1860
    monthsElapsed: number,    -- TI (starts at 1)

    -- Progression
    enemyHpPool: number,      -- EC
    enemyDamageScale: number, -- ED
    pirateEncounterBase: number, -- BP
    basePrices: { [number]: { [number]: number } }, -- BP%(port, good)

    -- Flags
    liYuenProtection: boolean,  -- LI (stored as number in BASIC, 0 or non-zero)
    liYuenLapseCounter: number, -- LI% (potentially vestigial)
    bankruptcyCount: number,    -- BL%
    wuWarningGiven: boolean,    -- WN

    -- Vestigial / tracking
    raftFactor: number,         -- RF (accumulated from thrown cargo, not read)

    -- Derived (recalculated)
    holdSpace: number,        -- MW: available space
    shipStatus: number,       -- percentage 0-100
}

export type CombatState = {
    totalEnemies: number,     -- SN: total remaining
    originalCount: number,    -- S0: original count
    onScreenEnemies: { { hp: number, maxHp: number, damage: number } },
    waitingToAppear: number,  -- SA: enemies not yet on screen
    booty: number,            -- BT: potential loot
    encounterType: number,    -- F1: 1=generic, 2=Li Yuen
    lastCommand: number,      -- LC: last action taken
    runMomentum: number,      -- OK: run success factor
    runAcceleration: number,  -- IK: run momentum increment
}

export type PortPrices = {
    [number]: number -- index 1-4 -> current price
}

export type GamePhase = "NAMING" | "PORT" | "TRADING" | "TRAVELING"
    | "COMBAT" | "STORM" | "ARRIVAL" | "EVENT" | "BANKRUPTCY"
    | "REPAIR" | "RETIREMENT" | "GAME_OVER"
```

**State Definitions:**
- **ARRIVAL** — Non-interactive processing cascade upon reaching a port. Covers time advancement, interest/debt compounding, January checks, and all automatic events (opium seizure, cargo theft, price calculation, Li Yuen lapse, price events, robbery). No player input required.
- **EVENT** — Interactive events that require player response: Li Yuen protection offer, ship repair, Wu visit (debt/borrow), ship upgrade offer, gun purchase offer.
- **BANKRUPTCY** — Emergency loan flow when player is completely broke. Wu offers a predatory loan; refusing ends the game.

### 3.3 Turn-Based Flow in Roblox

Roblox is fundamentally a real-time engine, so the turn-based flow needs to be managed explicitly. The recommended pattern is a **state machine driven by RemoteEvents**.

```
[Server: GameStateManager]
    |
    v
Phase: NAMING --> PORT --> TRADING <--> PORT
                    |                     |
                    v                     v
                  REPAIR              TRAVELING
                    |                     |
                    v                     v
                  PORT               COMBAT / STORM
                                          |
                                          v
                                       ARRIVAL (non-interactive cascade)
                                          |
                                          v
                                       EVENT (interactive events)
                                          |
                                          v
                                       BANKRUPTCY (if broke)
                                          |
                                          v
                                        PORT
                                          |
                                          v
                                     RETIREMENT / GAME_OVER
```

**Implementation pattern:**

```lua
-- Server: GameStateManager.lua

local currentPhase: GamePhase = "NAMING"

-- Client sends actions via RemoteEvents
PlayerActionEvent.OnServerEvent:Connect(function(player, action, data)
    if currentPhase == "PORT" then
        if action == "BUY" then
            handleBuy(player, data.goodIndex, data.quantity)
        elseif action == "SELL" then
            handleSell(player, data.goodIndex, data.quantity)
        elseif action == "TRANSFER" then
            handleTransfer(player, data.goodIndex, data.quantity, data.direction)
        elseif action == "BANK_DEPOSIT" then
            handleBankDeposit(player, data.amount)
        elseif action == "BANK_WITHDRAW" then
            handleBankWithdraw(player, data.amount)
        elseif action == "REPAY_DEBT" then
            handleRepayDebt(player, data.amount)
        elseif action == "BORROW" then
            handleBorrow(player, data.amount)
        elseif action == "REPAIR" then
            handleRepair(player, data.amount)
        elseif action == "QUIT_PORT" then
            handleSetSail(player, data.destination)
        elseif action == "RETIRE" then
            handleRetire(player)
        end
    elseif currentPhase == "COMBAT" then
        if action == "FIGHT" then
            handleFight(player)
        elseif action == "RUN" then
            handleRun(player)
        elseif action == "THROW_CARGO" then
            handleThrowCargo(player, data.goodIndex, data.quantity)
        end
    elseif currentPhase == "EVENT" then
        if action == "DIALOG_RESPONSE" then
            handleDialogResponse(player, data.dialogType, data.response)
        end
    elseif currentPhase == "BANKRUPTCY" then
        if action == "ACCEPT_LOAN" then
            handleAcceptLoan(player)
        elseif action == "REFUSE_LOAN" then
            handleRefuseLoan(player) -- game over
        end
    end

    -- After every action, send updated state to client
    StateUpdateEvent:FireClient(player, getGameState(), currentPhase)
end)
```

**The client never calculates game logic.** It sends intents ("I want to buy 50 Opium") and the server validates, processes, and returns the new state. The client renders whatever the server tells it.

### 3.4 UI Approach

The game's UI should be implemented entirely through Roblox's `ScreenGui` system within `StarterGui`. The 3D world serves as an atmospheric backdrop, not the primary interaction surface.

#### Screen Layout

**Main HUD (always visible during PORT phase):**

```
+------------------------------------------+
| Firm: [Name], Hong Kong                  |
| Date: Jan 1860    Ship Status: Perfect   |
+------------------------------------------+
| Hold    |  Warehouse  |  Ship Info       |
|---------|-------------|------------------|
| Opium: 0| Opium: 0   | Capacity: 60     |
| Silk: 0 | Silk: 0    | In Use: 0        |
| Arms: 0 | Arms: 0    | Vacant: 60       |
| Gen.: 0 | Gen.: 0    | Guns: 0          |
|---------|-------------|------------------|
| Cash: 400  Bank: 0  Debt: 5000          |
+------------------------------------------+
| Market Prices                            |
| Opium: 8000  Silk: 1200                 |
| Arms: 120    General: 12                |
+------------------------------------------+
| [Buy] [Sell] [Transfer] [Bank] [Repair] |
| [Visit Wu] [Set Sail] [Retire]          |
+------------------------------------------+
| Message Area                             |
+------------------------------------------+
```

**Combat HUD:**

```
+------------------------------------------+
| 15 ships attacking!  We have 5 guns      |
| Seaworthiness: Good (78%)               |
+------------------------------------------+
|  [Enemy Ship Grid - up to 10 ships]     |
|  [ visual ship sprites with HP bars ]   |
+------------------------------------------+
| [Run] [Fight] [Throw Cargo]             |
+------------------------------------------+
| Combat Log                               |
+------------------------------------------+
```

#### UI Module Organization

```
StarterGui/
  MainScreenGui/
    HUDFrame/
      FirmInfoBar
      ShipStatusPanel
      CargoPanel
      WarehousePanel (visible only in Hong Kong)
      FinanceBar
      MarketPricesPanel
      ActionButtonsFrame
      MessageLog
    CombatFrame/
      CombatHeader
      EnemyShipGrid
      CombatActions
      CombatLog
    DialogFrame/        -- Modal dialogs for events, Wu encounters, etc.
    NamingFrame/        -- Initial firm naming screen
    RetirementFrame/    -- Score display and rating
    GameOverFrame/
```

#### UI Implementation Notes

- Use `UIListLayout` and `UIGridLayout` for responsive arrangement
- All numeric displays should use the Big Number formatter (Thousand, Million, Billion, Trillion) matching the original game's style
- Event messages should appear in a scrolling message log with a brief delay between each, mimicking the original's pacing
- Combat actions should have keyboard shortcuts (R/F/T) in addition to click targets
- Modal dialogs for yes/no questions (Wu's offers, Li Yuen protection, ship upgrades) should pause the game flow until answered

### 3.5 Module Organization

```
src/
  server/
    GameStateManager.lua      -- Master state machine, phase transitions
    TradingEngine.lua         -- Price calc, buy/sell/transfer validation
    CombatEngine.lua          -- Combat state, round resolution
    EventEngine.lua           -- Random event generation and resolution
    NavigationEngine.lua      -- Travel, storm, blown-off-course logic
    FinanceEngine.lua         -- Bank, debt, Wu loans, interest
    ScoreEngine.lua           -- Final score and rating calculation
    DataPersistence.lua       -- DataStoreService save/load

  client/
    UIController.lua          -- Phase-driven UI state management
    InputHandler.lua          -- Key/click -> RemoteEvent dispatch
    HUDRenderer.lua           -- Updates HUD elements from state
    CombatRenderer.lua        -- Renders combat visuals and animations
    DialogManager.lua         -- Modal dialog display and response collection
    MessageLog.lua            -- Scrolling message display with timing
    SoundManager.lua          -- Sound effect triggers
    CameraManager.lua         -- Camera positioning per phase

  shared/
    GameConfig.lua            -- All constants, base prices, port names, etc.
    Types.lua                 -- Type definitions
    Enums.lua                 -- Enumeration values
    Validators.lua            -- Shared validation logic (e.g., can-afford checks)
    BigNumber.lua             -- Large number formatting utility
```

### 3.6 Communication Protocol

```lua
-- RemoteEvents (ReplicatedStorage/Remotes/)
local Remotes = {
    -- Client -> Server
    PlayerAction = RemoteEvent,      -- (action: string, data: table)
    StartGame = RemoteEvent,         -- (firmName: string, startChoice: number)

    -- Server -> Client
    StateUpdate = RemoteEvent,       -- (gameState: GameState, phase: GamePhase)
    CombatUpdate = RemoteEvent,      -- (combatState: CombatState, message: string)
    EventNotification = RemoteEvent, -- (eventType: string, eventData: table)
    DialogRequest = RemoteEvent,     -- (dialogType: string, dialogData: table)

    -- Client -> Server (dialog responses)
    DialogResponse = RemoteEvent,    -- (dialogType: string, response: any)

    -- RemoteFunctions (for synchronous queries)
    GetGameState = RemoteFunction,   -- () -> GameState
}
```

---

## 4. Roblox-specific Considerations

### 4.1 Port Representation

**Recommended approach: 3D backdrop with 2D UI gameplay.**

Each port should be a distinct 3D scene that the player's camera views while the 2D trading UI overlays it. This provides atmosphere without requiring complex 3D interaction.

**Port scenes (simple, atmospheric):**
- A harbor view with water, docked ships, and port-appropriate buildings
- Hong Kong: Victoria Harbor with junks and Western-style trading houses
- Shanghai: Bund-style waterfront
- Nagasaki: Japanese harbor architecture
- Saigon: French colonial style with sampans
- Manila: Spanish colonial Intramuros walls
- Singapore: Raffles-era colonial buildings
- Batavia: Dutch colonial architecture

**At sea (during travel):**
- Open ocean scene with the player's ship model sailing
- Storm scenes: dark skybox, rain particles, wave animation
- Combat scenes: enemy ship models arranged in a grid pattern facing the player's ship

**Per-Player 3D Scenes:**
- **StreamingEnabled** controls part streaming by proximity — it streams parts in and out based on how close the player's character (or `ReplicationFocus`) is to them. It does NOT provide per-player instancing of the 3D world.
- For per-player 3D scenes in a multiplayer server, use one of these approaches:
  - **Spatial separation:** Place each player's port scene geometry far apart in the world (e.g., 10,000+ studs between players), with each player's camera focused on their own scene area
  - **Cloned models:** Clone port scene models into player-specific folders and position them at unique coordinates
  - **Single shared scene:** If all players see the same backdrop (simplest approach), just use one scene and accept that all players see the same port. Since each player's game state is independent, the visual mismatch is cosmetic only.
- Use `Workspace` folders for each port scene, toggling visibility
- Or use a single ocean scene and swap skybox/lighting properties per port
- Port scenes are purely decorative -- no player character walking around

### 4.2 Ship Representation

The player's ship should be a 3D model visible during travel and combat:

- **Small ship** (starting): A lorcha or small junk model
- **Medium ship** (after upgrades): Larger junk or trading vessel
- **Large ship** (late game): Clipper ship or large merchantman

Ship model can swap based on capacity thresholds (e.g., <100: small, 100-300: medium, 300+: large).

**Enemy ships in combat:**
- Pirate junk models arranged in the 5x2 grid pattern from the original
- When hit, play a damage particle effect
- When sunk, play a sinking animation (ship tilts and submerges)
- When fleeing, ship sails off screen

### 4.3 Useful Roblox APIs

| API | Purpose |
|-----|---------|
| `DataStoreService` | Save/load game state across sessions |
| `TweenService` | Smooth animations for ship movement, UI transitions |
| `SoundService` | Ambient port sounds, combat SFX, storm audio |
| `Lighting` | Dynamic time-of-day and weather (storm darkness) |
| `ParticleEmitter` | Cannon fire, explosions, rain, waves |
| `Beam` | Cannon shot traces |
| `RemoteEvent` / `RemoteFunction` | Client-server communication |
| `TextService` | Text filtering for firm name input |
| `Players.PlayerRemoving` | Auto-save on disconnect |
| `game:BindToClose()` | Auto-save on server shutdown |
| `RunService.Heartbeat` | Smooth animation updates |
| `UserInputService` | Keyboard shortcut handling |

### 4.4 Data Persistence

```lua
-- server/DataPersistence.lua

local DataStoreService = game:GetService("DataStoreService")
local TaipanStore = DataStoreService:GetDataStore("TaipanSaves_v1")

local function saveGame(player: Player, state: GameState): boolean
    local key = "Player_" .. player.UserId
    local success, err = pcall(function()
        TaipanStore:SetAsync(key, {
            version = 1,
            timestamp = os.time(),
            state = serializeState(state),
        })
    end)
    if not success then
        warn("Failed to save game for", player.Name, err)
    end
    return success
end

local function loadGame(player: Player): GameState?
    local key = "Player_" .. player.UserId
    local success, data = pcall(function()
        return TaipanStore:GetAsync(key)
    end)
    if success and data then
        return deserializeState(data.state)
    end
    return nil
end
```

**Save triggers:**
- Arriving at any port (auto-save)
- Before player disconnects (`Players.PlayerRemoving`)
- **On server shutdown (`game:BindToClose()`)** — essential for Roblox, as the server may shut down without individual PlayerRemoving events firing (e.g., when the last player leaves and the server closes, or during Roblox maintenance). The `BindToClose` handler should iterate all active players and save their states.
- Manual save button in UI
- Before retirement score screen

```lua
-- Ensure saves on server shutdown
game:BindToClose(function()
    for _, player in ipairs(game.Players:GetPlayers()) do
        local state = getPlayerState(player)
        if state then
            saveGame(player, state)
        end
    end
end)
```

### 4.5 Text Filtering

Roblox requires all user-entered text to be filtered. The firm name must go through `TextService:FilterStringAsync()` before being stored or displayed.

```lua
local TextService = game:GetService("TextService")

local function filterFirmName(player: Player, rawName: string): string
    local success, result = pcall(function()
        local filterResult = TextService:FilterStringAsync(rawName, player.UserId)
        return filterResult:GetNonChatStringForBroadcastAsync()
    end)
    if success then
        return result
    end
    return "Trading Co."  -- fallback
end
```

### 4.6 Single-Player Considerations

Since this is a single-player game running in a Roblox multiplayer environment:

- Each player gets their own independent `GameState` instance on the server
- Multiple players can be in the same Roblox server but are playing completely separate games
- The 3D world can be shared (all players see the same port backdrop) or separated per player using spatial separation (geometry placed far apart) or cloned models — see section 4.1 for details
- Consider a lobby area where players can see each other before entering their individual game sessions
- Leaderboards (using `OrderedDataStore`) could show high scores across all players, adding a competitive element

### 4.7 Mobile Input

Roblox games are played across PC, console, and mobile devices. Keyboard shortcuts will not be available on mobile or console platforms, so all interactive elements must be touch-friendly:

- **Minimum touch target size:** 44dp (density-independent pixels) for all buttons and interactive elements. Roblox's equivalent is approximately 44 pixels at default UI scale.
- **All keyboard shortcuts must have on-screen button equivalents** — the shortcut keys (B/S/T, O/S/A/G, R/F/T, 1-7, Y/N) are convenience accelerators for PC, not the primary input method.
- **Consider a dedicated mobile layout** with larger buttons, simplified navigation, and reduced information density. The port HUD may need to be split into tabs (e.g., "Ship" / "Market" / "Actions") on smaller screens rather than showing everything at once.
- **Combat inputs** must be especially responsive on mobile — large, clearly labeled buttons for Run/Fight/Throw.
- **Numeric input** (for buy/sell quantities): provide a numeric keypad UI rather than relying on the system keyboard, which can be slow and disruptive on mobile.
- **"All" button** should be prominently placed next to numeric inputs as a touch target, since typing "A" on a mobile keyboard is cumbersome.

---

## 5. Key Implementation Challenges

### 5.1 Faithful Random Number Distribution

The original game's `FN R(X) = INT(USR(0) * X)` generates integers from 0 to X-1 using a custom machine-language random number generator. Roblox's `math.random()` is suitable but must be carefully bounded:

```lua
-- Equivalent of FN R(X): returns integer in [0, x-1]
local function fnR(x: number): number
    if x <= 0 then return 0 end
    return math.random(0, math.floor(x) - 1)
end
```

The `FN R(X)` function is called with non-integer arguments in several places (e.g., `FN R(CA/1.8)`, `FN R(DM/SC*3)`). The floor must happen inside `math.random`, not on the argument.

Special attention: `FN R(0)` returns 0 in the original (it never calls random with 0). Several game mechanics rely on this behavior as a guard (e.g., `FN R(4)` being truthy 3/4 of the time).

### 5.2 Large Number Handling

Taipan's values can reach into the trillions. Lua uses 64-bit double-precision floats, which provide exact integer representation up to 2^53 (~9 quadrillion). This is sufficient for Taipan's range, but care must be taken:

- Always use `math.floor()` where the original uses `INT()`
- The Big Number display formatter must handle Thousand, Million, Billion, Trillion labels
- DataStore serialization must not lose precision (Roblox JSONEncode can handle numbers up to 2^53)

```lua
-- shared/BigNumber.lua
local function formatBigNumber(n: number): string
    n = math.floor(n)
    if math.abs(n) < 1e6 then
        return tostring(n)
    end

    local suffixes = {
        { threshold = 1e12, label = " Trillion" },
        { threshold = 1e9,  label = " Billion" },
        { threshold = 1e6,  label = " Million" },
        { threshold = 1e3,  label = " Thousand" },
    }

    for _, s in ipairs(suffixes) do
        if math.abs(n) >= s.threshold then
            local scaled = n / s.threshold
            -- Show up to 3 significant digits
            local formatted = string.format("%.1f", scaled)
            -- Remove trailing .0
            formatted = formatted:gsub("%.0$", "")
            return formatted .. s.label
        end
    end

    return tostring(n)
end
```

### 5.3 Combat Pacing

The original game reads keyboard input in real-time during a delay loop, allowing the player to queue their next action while watching combat animations. In Roblox:

- Combat rounds should be animated with `TweenService` (cannon fire, hits, sinking)
- The player should be able to select their next action *during* enemy fire animations (not forced to wait)
- Use a coroutine or Promise-based system to handle the async flow:

```lua
-- Pseudocode for combat round flow
local function executeCombatRound(action, data)
    -- 1. Resolve player action (server-side)
    local result = resolvePlayerAction(action, data)

    -- 2. Send result to client for animation
    CombatUpdate:FireClient(player, result, combatState)

    -- 3. Wait for animation acknowledgment (with timeout)
    local ack = waitForClientAck(player, 5) -- 5 second timeout

    -- 4. If enemies remain, resolve enemy fire
    if combatState.totalEnemies > 0 then
        local enemyResult = resolveEnemyFire()
        CombatUpdate:FireClient(player, enemyResult, combatState)
        waitForClientAck(player, 5)
    end

    -- 5. Check end conditions
    checkCombatEnd()
end
```

**Important: Throw Cargo chains into Run.** When the player chooses "Throw Cargo", the server should resolve the throw (removing cargo, boosting run momentum), then immediately resolve a run attempt — without returning to the player for another action choice. The client should animate both the throw and the run attempt as a single sequence.

### 5.4 State Machine Complexity

The game has many interlocking phases with conditional transitions. The state machine must handle:

- Arriving at a port triggers a cascade: bank interest, debt compounding, time advance, then sequential event checks in the exact order documented in section 2.10
- Each interactive event may require a yes/no dialog, which is async in Roblox
- Events must execute in the correct order and some are conditional on others
- Post-combat event chaining means combat resolution can lead back into storm checks or Li Yuen encounters

**Recommended approach:** Use a sequential event queue processed on the server, with the ARRIVAL phase handling non-interactive events and the EVENT phase handling interactive ones:

```lua
local function processArrival(port: PortId)
    -- ARRIVAL phase: non-interactive processing
    currentPhase = "ARRIVAL"

    -- Time and financial updates
    advanceTime()
    compoundInterest()
    compoundDebt()
    checkJanuaryUpdates()

    -- Build event queue (ordered per section 2.10)
    local events = {}

    if port == 1 then -- Hong Kong
        -- Interactive events (will switch to EVENT phase)
        checkLiYuenProtectionOffer(events)  -- line 1040
        checkShipRepair(events)              -- line 1120
        checkWuWarning(events)               -- line 1210 (narrative, non-interactive)
        checkWuVisit(events)                 -- line 1310 (interactive: debt/borrow)
        checkWuEnforcers(events)             -- line 1460 (after Wu visit)
    end

    checkShipUpgrade(events)                 -- line 1610
    checkGunPurchase(events)                 -- line 1710

    -- Non-interactive events (ARRIVAL phase continues)
    checkOpiumSeizure(events)                -- line 1900
    checkCargoTheft(events)                  -- line 2000
    calculatePrices()                        -- line 2100
    checkLiYuenLapse(events)                 -- line 2310
    checkLiYuenWarning(events)               -- line 2330
    checkPriceEvent(events)                  -- line 2410
    checkCashRobbery(events)                 -- line 2500

    -- Process events sequentially
    for _, event in ipairs(events) do
        if event.interactive then
            currentPhase = "EVENT"
        end
        local response = presentEventToPlayer(event) -- async for interactive events
        resolveEvent(event, response)
    end

    -- Check for bankruptcy
    if isPlayerBroke() then
        currentPhase = "BANKRUPTCY"
        handleBankruptcy()
        return
    end

    currentPhase = "PORT"
    sendStateUpdate()
end
```

### 5.5 Preventing Client-Side Cheating

Since all game state lives on the server, the primary attack vector is sending fraudulent RemoteEvent calls. Defenses:

1. **Validate every action server-side:** Never trust client-supplied quantities, amounts, or indices
2. **Check phase validity:** Reject buy/sell actions during combat, etc.
3. **Rate-limit actions:** Prevent rapid-fire RemoteEvent spam
4. **Sanity-check values:** Reject negative quantities, quantities exceeding inventory, etc.

```lua
local function handleBuy(player, goodIndex, quantity)
    -- Validate phase
    if currentPhase ~= "PORT" then return end

    -- Validate good index
    if goodIndex < 1 or goodIndex > 4 then return end

    -- Validate quantity
    if type(quantity) ~= "number" then return end
    quantity = math.floor(quantity)
    if quantity <= 0 then return end

    -- Validate affordability
    local cost = quantity * currentPrices[goodIndex]
    if cost > state.cash then return end

    -- Validate hold space
    if quantity > state.holdSpace then return end

    -- Execute
    state.cash = state.cash - cost
    state.shipCargo[goodIndex] = state.shipCargo[goodIndex] + quantity
    recalculateHoldSpace()
    sendStateUpdate()
end
```

### 5.6 Balancing the Economy

The original game's economy is tuned around its specific random number generator and price distributions. When porting:

- Test extensively that price swings create real profit opportunities
- Verify that debt compounding at 10%/month is appropriately punishing (it doubles roughly every 7 months)
- Confirm that the late-game scaling (enemy HP, damage, fleet sizes) provides genuine challenge
- The millionaire threshold should be achievable in 15-40 months of play with skilled trading
- The score formula's time penalty means there is a "sweet spot" -- trading too long reduces score even if wealth grows
- **Note that TI starts at 1**, so formulas like `(TI + 5) / 6` evaluate to 1.0 on the first turn, not 0.83

### 5.7 UI Responsiveness and Feel

The original game's charm partly comes from its text-based immediacy -- actions resolve instantly with text feedback. In Roblox:

- Keep UI transitions snappy (< 200ms for panel swaps)
- Use typewriter-style text animation for event messages (matching the original's line-by-line reveal)
- Keyboard shortcuts are essential for PC: experienced players should never need to click
  - B/S/T for Buy/Sell/Transfer
  - O/S/A/G for Opium/Silk/Arms/General
  - R/F/T for Run/Fight/Throw in combat
  - Number keys 1-7 for port selection
  - Y/N for yes/no dialogs
- **All shortcuts must have on-screen button equivalents for mobile/console** (see section 4.7)
- The message log should auto-scroll but allow scroll-back to review past events

### 5.8 Preserving the Atmosphere

The game's historical flavor is important. Beyond the 3D port backdrops:

- Use period-appropriate fonts (serif fonts where possible, or Roblox equivalents)
- Color palette: parchment tones, ink blacks, jade greens -- avoid modern neon colors
- Sound design: creaking wood, harbor bells, seagulls, distant shouting, cannon fire
- Address the player as "Taipan" in all game messages, matching the original's tone
- Preserve the original's colorful dialogue: "Sunk 3 of the buggers, Taipan!!", "Bad joss!!", "Good joss!!"
- The Li Yuen protection system and Elder Brother Wu's loan sharking should feel threatening and atmospheric, not gamified

### 5.9 Session Length and Save Points

Unlike the original Apple II game (played in one sitting), Roblox players may have short sessions:

- Auto-save at every port arrival
- Allow mid-combat saves (serialize full CombatState)
- On reconnect, restore the exact game phase (including mid-voyage events)
- Consider a "travel log" that summarizes what happened in previous sessions for returning players
- Target 20-45 minutes for a complete game (similar to the original)

### 5.10 Accessibility and Onboarding

The original game assumed players would read the manual. For Roblox:

- Add a brief tutorial overlay on first play (explain the goal: buy low, sell high, get rich)
- Tooltip on each good showing its price range and which ports tend to be cheap/expensive
- A "Price History" feature showing the best prices the player has seen (the book version included this as the "Records" feature)
- Clear visual indicators of which port is selected and the meaning of each stat
- An optional "Advisor" toggle that highlights obviously good deals (e.g., a price crash event) for new players

---

## 6. Appendix A: BASIC Variable Reference

This table maps BASIC variable names from the original source to their Lua equivalents in the Roblox implementation. Use this as a cross-reference when verifying game logic against the BASIC source.

### Game State Variables

| BASIC | Lua Name | Type | Description |
|-------|----------|------|-------------|
| `CA` | `cash` | number | Player's liquid cash |
| `BA` | `bankBalance` | number | Bank account balance (Hong Kong) |
| `DW` | `debt` | number | Debt owed to Elder Brother Wu |
| `SC` | `shipCapacity` | number | Total ship hold capacity |
| `MW` | `holdSpace` | number | Available (vacant) hold space |
| `GN` | `guns` | number | Number of guns on ship |
| `DM` | `damage` | number | Accumulated damage points |
| `LO` | `currentPort` | PortId | Current port index (1-7, 0 = at sea) |
| `D` | `destination` | PortId | Travel destination port |
| `TI` | `monthsElapsed` | number | Total months elapsed (starts at 1) |
| `MO` | `month` | number | Current month (1-12) |
| `YE` | `year` | number | Current year (starts 1860) |
| `LI` | `liYuenProtection` | boolean/number | Li Yuen protection flag (0 = unprotected) |
| `LI%` | `liYuenLapseCounter` | number | Months since protection lapsed (potentially vestigial) |
| `WN` | `wuWarningGiven` | boolean | Whether Wu's braves warning has fired |
| `BL%` | `bankruptcyCount` | number | Number of emergency loans taken |
| `BP` | `pirateEncounterBase` | number | Base pirate encounter denominator (7 or 10) |
| `EC` | `enemyBaseHP` | number | Enemy HP pool base (starts 20, +10/year) |
| `ED` | `enemyBaseDamage` | number | Enemy damage base (starts 0.5, +0.5/year) |
| `WC` | `warehouseCapacity` | number | Warehouse max capacity (10,000) |
| `WS` | `warehouseUsed` | number | Current warehouse usage |
| `RF` | `raftFactor` | number | Accumulated from thrown cargo (potentially vestigial) |

### Cargo Arrays

| BASIC | Lua Name | Description |
|-------|----------|-------------|
| `ST(1,J)` | `warehouseCargo[J]` | Warehouse cargo for good J (1-4) |
| `ST(2,J)` | `shipCargo[J]` | Ship hold cargo for good J (1-4) |
| `CP(I)` | `currentPrices[I]` | Current price for good I at current port |
| `BP%(I,J)` | `basePrices[I][J]` | Base price for good J at port I |

### Combat Variables

| BASIC | Lua Name | Type | Description |
|-------|----------|------|-------------|
| `SN` | `totalEnemies` | number | Total remaining enemy ships |
| `S0` | `originalCount` | number | Original enemy count at start of battle |
| `SA` | `waitingToAppear` | number | Enemies not yet shown on screen |
| `SS` | `onScreenCount` | number | Currently visible enemy ships |
| `F1` | `encounterType` | number | 1 = generic pirates, 2 = Li Yuen's fleet |
| `BT` | `booty` | number | Potential loot from victory |
| `OK` | `combatResult` / `runMomentum` | number | Run momentum during combat; outcome code after (0=sunk, 1=won, 2=Li Yuen saved, 3=fled) |
| `IK` | `runAcceleration` | number | Run momentum increment |
| `LC` | `lastCommand` | number | Last combat command (0=none, 1=run, 2=fight, 3=throw) |
| `CMD` | `currentCommand` | number | Current combat command selection |
| `SK` | `shipsKilled` | number | Ships sunk this round |
| `AM%(I,0)` | `onScreenEnemies[I].maxHp` | number | Enemy ship I max HP (0 = empty slot) |
| `AM%(I,1)` | `onScreenEnemies[I].damage` | number | Enemy ship I accumulated damage |

### Display / UI Variables

| BASIC | Lua Name | Description |
|-------|----------|-------------|
| `H$` | `firmName` | Player's firm name |
| `T$` | `playerTitle` | Always "Taipan" — used in all messages addressing the player |
| `CO$(I)` | `GOOD_NAMES[I]` | Commodity name for good I |
| `LO$(I)` | `PORT_NAMES[I]` | Port name for port I |
| `ST$(I)` | `STATUS_LABELS[I]` | Ship status label for bracket I (0-5) |

### Constants and Configuration

| BASIC | Lua Name | Value | Description |
|-------|----------|-------|-------------|
| `T` | `DELAY_BASE` | 300 | Base delay loop count for animations |
| `LT` | `LOG_10` | `math.log(10)` | Precomputed log(10) for big number formatting |

### Input Variables

| BASIC | Lua Name | Description |
|-------|----------|-------------|
| `W` | (context-dependent) | Generic numeric input value |
| `WK$` | (context-dependent) | Generic string input buffer |
| `R1%` | `isAllInput` | Flag: true when player entered "A" (All) |
| `CH$` | `validChoices` | String of valid input characters for current prompt |
| `CH%` | `choiceIndex` | Index of chosen character within CH$ |
| `WU%` | `isWuPrompt` | Flag: modifies input behavior during Wu visit |
