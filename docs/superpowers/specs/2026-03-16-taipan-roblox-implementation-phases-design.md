# Taipan! Roblox — Implementation Phases Design Spec

**Date:** 2026-03-16
**Author:** Brian Herlihy
**Status:** Approved

---

## Context

A single-player Roblox implementation of the classic Apple II game Taipan (Ronald J. Berg version: 7 ports, 4 goods). The full game mechanics are documented in `/mnt/d/dev/Taipan/DESIGN_DOCUMENT.md` (v3.0). The annotated BASIC source is at `/mnt/d/dev/Taipan/BASIC_ANNOTATED.md`.

**Constraints:**
- Solo developer
- Some prior Roblox experience
- Pure 2D ScreenGui — no 3D world
- Goal: publish to Roblox platform

---

## Phasing Approach

Vertical slices. Each phase ends with something playable and testable. Systems are introduced in order of player-visible impact so feel and balance issues surface early.

---

## Phase 1: Foundation + Trading Loop

**Playable outcome:** Buy and sell goods at Hong Kong. Prices fluctuate. You can go broke.

### Deliverables
- Roblox Studio project with folder structure per design doc (`ServerScriptService`, `ReplicatedStorage/shared`, `StarterGui`)
- Core modules scaffolded: `GameState`, `Constants`, `PriceEngine`, `RemoteEvents`
- `GameState` initialised for both starting choices (cash start: 400 cash, 5000 debt, 60 hold, 0 guns; guns start: 0 cash, 0 debt, 10 hold, 5 guns)
- Price calculation: `BP%(LO,I)/2 * (FN_R(3)+1) * 10^(4-I)` including crash/boom events (1-in-9 chance per good per arrival)
- Buy/sell mechanics with hold capacity enforcement and overload prevention
- "A" (All) shortcut on all numeric inputs
- ScreenGui panels: inventory (hold + warehouse side-by-side), current prices table, cash/debt/bank strip, action buttons
- "End Turn" recalculates prices (travel comes in Phase 2)

### Out of Scope
Travel, Wu, bank, Li Yuen, combat, events, save/load.

### Milestone Test
Buy opium cheap, wait for a boom event, sell at profit. Fill hold beyond capacity and confirm overload is blocked.

---

## Phase 2: Travel + All Ports + Time

**Playable outcome:** Sail between all 7 ports. Debt starts hurting.

### Deliverables
- Port selection UI listing all 7 destinations
- Departure and arrival flow; `D=0` guard (no interest/debt compounding on first turn of game)
- Time advance per voyage: `TI++`, `MO++`, `YE` rolls over; 0.5% bank interest, 10% debt compound
- All 7 ports with correct base price matrices (from design doc section 2.2)
- Annual January event (fires once per in-game year when `MO` resets to 1): base price drift (`BP%` increments 0 or 1 randomly for all ports/goods), `EC += 10`, `ED += 0.5`
- Menu options by location: non-HK shows Buy/Sell/Quit; HK shows Buy/Sell/Quit/Transfer/Visit Wu (Wu greyed out until Phase 3)
- Warehouse transfer UI: move goods between hold and warehouse (bidirectional per good)
- Overload check on departure (`MW < 0` blocks sailing)

### Out of Scope
Wu, bank, Li Yuen, combat, events, save/load.

### Milestone Test
Start in Hong Kong in debt. Trade across 3+ ports. Watch debt compound voyage by voyage. Confirm January triggers EC/ED scaling.

---

## Phase 3: Financial System

**Playable outcome:** Elder Brother Wu is breathing down your neck. The bank pays interest.

### Deliverables
- Bank deposit/withdraw UI (Hong Kong only)
- Wu visit flow (full sequence):
  - Debt repayment prompt skipped if `DW=0` OR `CA=0` (line 1360)
  - Borrow up to `2×CA`; borrowed amount added to both `CA` and `DW`
  - Bankruptcy emergency loan: `FN_R(1500)+500`, repayment = `FN_R(2000)*BL% + 1500`; `BL%` increments each use
- Wu warning: triggers when `DW >= 10000`, `WN` not set, `D != 0`; sends 50–149 braves, sets `WN=1` (fires once only)
- Wu's enforcers: `DW > 20000`, 1-in-5 chance after Wu visit; steals all cash, kills 1–3 bodyguards
- Li Yuen protection offer in HK: skipped if `LI != 0` OR `CA = 0`; cost `FN_R(CA/1.8)` when `TI <= 12`, `FN_R(CA) + FN_R(1000*TI) + 1000*TI` when `TI > 12`
- Li Yuen protection lapse: `LI = LI AND FN_R(20)` each arrival (1-in-20 chance of losing protection)
- Li Yuen warning message: fires when unprotected, not in HK, 3-in-4 chance (`FN_R(4)` truthy)
- `LI%` — confirmed dead code; not implemented

### Out of Scope
Combat, random events (opium/theft/robbery/storm), save/load.

### Milestone Test
Ignore debt past 10,000 to trigger Wu's warning. Continue to 20,000+ and trigger enforcers. Take emergency loans and watch `BL%` worsen repayment terms.

---

## Phase 4: Random Events + Storm

**Playable outcome:** Every voyage carries risk.

### Deliverables
All events fire in arrival order per design doc section 2.10:
- **Opium seizure** (HK excluded): triggers when `ST(2,1) != 0` (ship hold opium), 1-in-18; confiscates all hold opium (`ST(2,1) = 0`), restores hold capacity (`MW += opium_amount`), costs `FN_R(CA/1.8)` cash
- **Cargo theft**: triggers when warehouse total `> 0`, 1-in-50; each warehouse good `ST(1,J)` reduced to `FN_R(amount/1.8)`, `WS` counter updated (`WS = WS - W + WW`)
- **Cash robbery**: `CA > 25000`, 1-in-20; loses `FN_R(CA/1.4)`
- **Storm**: 1-in-10 per voyage; "going down" check 1-in-30; sink check `FN_R(DM/SC*3)` truthy; blown off course 1-in-3 (random non-destination port; BASIC line 3330: `IF FN_R(3) THEN 3350` skips blow-off 2/3 of the time)
- Game over screen on ship sunk

### Out of Scope
Combat, ship repair (Phase 6), save/load.

### Milestone Test
Carry opium to a non-HK port and get seized. Fill warehouse and get robbed (confirm `WS` updates correctly). Accumulate damage from storms until ship sinks.

---

## Phase 5: Combat

**Playable outcome:** Fight pirates, run, or throw cargo.

### Deliverables
- Generic pirate encounter: `FN_R(BP)=0`; fleet size `FN_R(SC/10+GN)+1`
- Li Yuen's pirates: 1-in-4 unprotected (`FN_R(4)=0`), 1-in-12 protected (`FN_R(4+8*LI)=0`); protected → let pass
- Combat loop with Fight / Run / Throw Cargo actions
- `AM%` 10-slot enemy grid: `AM%(I,0)` = max HP, `AM%(I,1)` = damage taken; spawn-on-vacancy algorithm (`SA`, `SS` counters)
- Grid position formula (BASIC line 5880): slot I → X = `(I - INT(I/5)*5)*8+1`, Y = `INT(I/5)*6+7` (equivalent to `(I mod 5)*8+1` for integer I)
- Run momentum: `OK`/`IK` counters; throw cargo auto-triggers run (`GOTO 5210`); `RF` accumulates but is not read (vestigial)
- Run success: `FN_R(OK) > FN_R(SN)`; on failure, if `SN > 2` and `FN_R(5)=0` a partial escape occurs (lose `FN_R(SN/2)+1` ships); otherwise combat resumes from enemy fire, then back to command selection
- Player gun fire: random slot retry on empty slot (loop guard: only fire when `SN > 0`); damage `FN_R(30)+10`
- Enemy fire: `DM += FN_R(ED*I*F1) + I/2` where `I = min(SN,15)`
- Gun destruction: `FN_R(100) < (DM/SC)*100` OR `(DM/SC)*100 > 80`
- Li Yuen intervention: 1-in-20 when `F1=1` (generic pirates only)
- Booty on victory: `FN_R(TI/4*1000*SN^1.05) + FN_R(1000) + 250`
- Post-combat chaining: OK=1 (victory) → storm check; OK=2 (Li Yuen saved) → Li Yuen re-check; OK=3 (ran) → storm check
- In-combat ship status panel uses **truncation** (`INT(DM/SC*100)`, BASIC line 5160); the main inventory/status screen uses **rounding** (`INT(DM/SC*100+0.5)`, BASIC line 313) — both must be implemented as-is; do not unify them

### Out of Scope
Ship repair/upgrade (Phase 6), save/load.

### Milestone Test
Fight pirates with 5 guns. Survive with heavy damage. Run from a second encounter. Confirm post-combat storm can chain after a successful run.

---

## Phase 6: Ship Progression + Score + Retirement

**Playable outcome:** Grow your empire. Know when you've won.

### Deliverables
- Ship repair: cost-per-damage-unit `BR = INT((FN_R(60*(TI+3)/4) + 25*(TI+3)/4) * SC/50)`; player inputs cash amount `W` to spend; damage repaired `= INT(W/BR + 0.5)` (rounds to nearest); "All" input sets `W = BR*DM+1` (the `+1` ensures rounding fully covers all damage)
- Ship upgrade offer: 1-in-4 chance (`FN_R(4)` truthy skips); cost `INT(1000 + FN_R(1000*(TI+5)/6)) * (INT(SC/50)*(DM>0)+1)`; adds 50 capacity, repairs all damage
- Gun purchase offer: 1-in-3 chance (`FN_R(3)` truthy skips); requires `MW >= 10`; cost `INT(FN_R(1000*(TI+5)/6)+500)`
- Score formula: `INT((CA+BA-DW)/100/TI^1.1)`
- Rating thresholds: Ma Tsu (≥50000), Master (8000–49999), Taipan (1000–7999), Compradore (500–999), Galley Hand (<500)
- Retirement option `R` appears in HK menu when net worth ≥ 1,000,000; sets `OK=16`
- Full game over screen for all endings: sunk, quit, retired

### Out of Scope
Save/load (Phase 7).

### Milestone Test
Reach net worth 1,000,000, retire, see correct score and "Ma Tsu" rating. Also test quitting broke to confirm "Galley Hand" rating.

---

## Phase 7: Persistence + Polish

**Playable outcome:** Game survives disconnects and feels good on all devices.

### Deliverables
- DataStore save/load with `dataStoreRetry()` wrapper: exponential backoff, 3 attempts, short delays in `BindToClose`
- `game:BindToClose()` as failsafe save alongside `Players.PlayerRemoving`
- Save on port departure (dirty-flag pattern); respects DataStore rate limit (~60 + 10×playerCount SetAsync/min)
- Save schema includes `version` field for future migrations
- Per-player state maps throughout (`playerStates[player]`); no global state
- `RequestStateUpdate` RemoteEvent replaces any RemoteFunction (eliminates client yield attack surface)
- Mobile: all interactive elements ≥ 44dp touch targets; layout verified on portrait phone viewport
- UI polish: consistent amber/green terminal colour palette, smooth panel transitions
- Onboarding: brief contextual help on first play (Wu, Li Yuen, warehouse explained inline)
- `TextService:FilterStringAsync` applied to all player-visible strings

### Milestone Test
Play a full game, force-close Roblox mid-voyage, reopen and confirm resume from correct port with correct state. Play on a phone-sized window and confirm all buttons are reachable.

---

## Phase 8: Publishing Prep

**Playable outcome:** Live on Roblox.

### Deliverables
- Final audit of all formulas against `BASIC_ANNOTATED.md`
- Edge case testing checklist:
  - Guns start (0 cash, 0 debt path)
  - `DM` fractional accumulation across multiple combat rounds
  - `D=0` first-turn guard
  - Overloaded hold on departure attempt
  - `BL%` counter at high values (late emergency loans)
  - Annual January event at `TI=13` (first year `TI>12` for Li Yuen cost formula)
- Roblox content policy check on "Opium" good — rename if required (e.g. "Medicine" or "Spices") or add content disclaimer
- Game icon, description, ≥3 screenshots/thumbnails
- Experience set to public with age recommendation and genre tags
- Smoke-test live on platform (not just Studio) on both desktop and mobile

### Milestone Test
A fresh player with no knowledge of the original can start, understand the basic loop, and reach turn 10 without reading external documentation.

---

## Summary

| Phase | Key Systems | Playable? |
|-------|------------|-----------|
| 1 | Foundation, trading loop, prices | Hong Kong buy/sell |
| 2 | Travel, all ports, time advance | Full trade route |
| 3 | Wu, bank, Li Yuen | Full economic pressure |
| 4 | Random events, storm | Dangerous voyages |
| 5 | Combat | Fight or flee pirates |
| 6 | Ship progression, score, retirement | Win condition |
| 7 | Persistence, polish, mobile | Production-ready |
| 8 | Edge cases, compliance, publish | Live on Roblox |
