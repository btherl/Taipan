# Phase 7: Persistence + Polish — Design Spec

**Date:** 2026-03-18
**Author:** Brian Herlihy
**Status:** Approved

---

## Context

Phase 7 is the final development phase before publishing prep (Phase 8). It adds DataStore persistence so player progress survives disconnects, a mobile layout pass to meet touch target standards, and a colour audit to ensure consistent visual polish. Phase 6 left the game fully playable with a win condition; Phase 7 makes it production-ready.

**Reference:** Phase overview in `docs/superpowers/specs/2026-03-16-taipan-roblox-implementation-phases-design.md` (Phase 7 section).

---

## Decisions

| Topic | Decision |
|---|---|
| Persistence scope | Canonical fields only (not computed fields); always save, including game-over state |
| Mobile | Full layout pass: 44px minimum touch targets + spacing/font review |
| Transitions | None — instant state changes suit the terminal aesthetic |
| Polish | Colour audit: enforce consistent amber/green/red/grey palette across all panels |
| Onboarding | DataStore-gated first-play Notify messages on first HK arrival (`seenTutorial` flag) |
| TextService | Skip — no player-generated text in this game |

---

## Architecture

Three tasks, in dependency order:

1. **PersistenceEngine** — pure logic module (serialise, deserialise, retry wrapper)
2. **GameService wiring** — DataStore save/load integrated into server event handlers
3. **UI polish pass** — mobile touch targets + colour audit across all panels

---

## Task 1: PersistenceEngine

### New file
`src/ReplicatedStorage/shared/PersistenceEngine.lua`

### Canonical fields (saved to DataStore)

```
startChoice, cash, debt, bankBalance,
shipCapacity, shipCargo[1..4], guns, damage,
warehouseCargo[1..4], basePrices,
currentPort, month, year, turnsElapsed,
liYuenProtection, wuWarned, wuBailoutCount,
enemyBaseDamage, enemyBaseHP,
gameOver, gameOverReason, finalScore, finalRating,
seenTutorial
```

### Derived on load (not saved)

| Field | How derived |
|---|---|
| `holdSpace` | `shipCapacity - Σshipcargo - guns×10` |
| `warehouseUsed` | `Σwarehousecargo` |
| `currentPrices` | `PriceEngine.calculatePrices(basePrices, currentPort)` |
| `destination` | Set to `currentPort` |
| `liYuenOfferCost` | `nil` — recalculated on next HK arrival |
| `inWuSession` | `false` — reset on load |
| `combat` | `nil` — ephemeral; player resumes at port with no active combat |
| `shipOffer` | `nil` — ephemeral; regenerated on next HK arrival |

### Schema

Saved table includes `version = 1` for future migration support.

### Functions

**`PersistenceEngine.serialize(state)`**
Returns a plain table containing all canonical fields plus `version = 1`. Does not mutate `state`.

**`PersistenceEngine.deserialize(data, PriceEngine)`**
Takes a saved data table and `PriceEngine` (dependency injection for testability). Returns a full state table with all canonical fields restored and all derived fields populated. Returns `nil` if `data` is nil or `data.version` is missing/unrecognised.

**`PersistenceEngine.dataStoreRetry(fn, maxAttempts)`**
Calls `fn()` up to `maxAttempts` times (default 3). On failure, waits 1s, 2s, 4s (exponential backoff) before retrying. Returns the result on success, or `nil` on total failure. Errors are caught with `pcall`; failures are logged via `warn()`.

### Tests
`tests/PersistenceEngine.spec.lua` — covers:
- `serialize` produces a table with `version = 1`
- `serialize` includes all canonical fields
- `deserialize` restores all canonical fields
- `deserialize` computes derived fields correctly (`holdSpace`, `warehouseUsed`, `destination`)
- `deserialize` returns `nil` for nil input
- `deserialize` returns `nil` for data with missing `version`
- `dataStoreRetry` returns result on first-call success
- `dataStoreRetry` retries on failure and returns result on later success
- `dataStoreRetry` returns `nil` after exhausting all attempts

---

## Task 2: GameService DataStore Wiring + Onboarding

### Modified file
`src/ServerScriptService/GameService.server.lua`

### DataStore setup (top of file)

```lua
local DataStoreService = game:GetService("DataStoreService")
local gameStore = DataStoreService:GetDataStore("TaipanV1")
```

### Helper: `savePlayer(player, state)`

- Calls `PersistenceEngine.serialize(state)`
- Calls `PersistenceEngine.dataStoreRetry` wrapping `gameStore:SetAsync("player_" .. player.UserId, data)`
- Silent on failure — logs via `warn()`, does not crash or surface to client

### Helper: `loadPlayer(player)`

- Calls `PersistenceEngine.dataStoreRetry` wrapping `gameStore:GetAsync("player_" .. player.UserId)`
- Returns `PersistenceEngine.deserialize(data, PriceEngine)`, or `nil` if no save found

### `ChooseStart` handler (modified)

1. Try `loadPlayer(player)`
2. If data found: restore state, push to client — skip `GameState.newGame`
3. If nil: `GameState.newGame` as before; `seenTutorial = false`

### `TravelTo` handler (modified)

- Call `savePlayer(player, state)` after `pushState(player)` on every departure (dirty-flag pattern)

### `Players.PlayerRemoving` (modified)

- Call `savePlayer(player, state)` before `playerStates[player] = nil`

### `game:BindToClose()` (new)

```lua
game:BindToClose(function()
  for player, state in pairs(playerStates) do
    savePlayer(player, state)
    task.wait(0)
  end
end)
```

The `task.wait(0)` yields between saves to stay within Roblox's ~30s `BindToClose` budget.

### Onboarding

On `ChooseStart` when `seenTutorial == false` (new game only), store the flag to fire on first HK arrival. In the `TravelTo` handler, when `destination == HONG_KONG` and `state.turnsElapsed == 1` and `not state.seenTutorial`:

```
"Welcome, Taipan! Visit Elder Brother Wu to borrow cash or repay your debt."
"Use the Warehouse to store goods safely between voyages — holds up to 10,000 units."
"Li Yuen commands the seas. Pay for his protection in Hong Kong to avoid his fleet."
```

After firing: set `state.seenTutorial = true`, call `savePlayer` immediately to persist the flag.

---

## Task 3: UI Polish Pass

### Mobile — 44px touch target floor

All `TextButton` and `TextBox` instances currently sized at 28px tall are raised to 44px. Downstream panel heights and position cascades are adjusted as needed.

| Panel | Elements affected |
|---|---|
| `BuySellPanel.lua` | Buy, Sell, End Turn buttons; quantity input box |
| `WarehousePanel.lua` | Transfer To/From buttons; quantity input box |
| `WuPanel.lua` | Repay, Borrow, Leave, Protection buttons; amount input box |
| `BankPanel.lua` | Deposit, Withdraw buttons; amount input box |
| `ShipPanel.lua` | Repair, All, Done buttons; amount input box; Accept/Decline pairs |
| `CombatPanel.lua` | Fight, Run, Throw buttons; quantity input box |
| `GameOverPanel.lua` | Restart button |
| `PortPanel.lua` | Retire, Quit buttons (port travel buttons already 50px) |

### Colour audit — enforce palette

| Role | RGB | Applied to |
|---|---|---|
| Amber `(200, 180, 80)` | Titles, labels, data values, date |
| Green `(140, 200, 80)` | Action buttons, port names, positive outcomes |
| Red `(220, 80, 80)` | Quit, game-over, sunk state |
| Orange `(220, 120, 60)` | Repair/damage (warning tone) |
| Blue `(120, 120, 220)` | Gun purchase (distinct action type) |
| Grey `(80, 80, 80)` | Disabled elements, current port button |

Any button or label using an ad-hoc colour is moved to the nearest palette entry. No new layout or spacing changes beyond what the mobile pass requires.

### No automated tests for Task 3

Visual verification via Studio injection and manual review.

---

## Milestone Test

1. Play a game, travel to several ports, then force-quit Roblox.
2. Reopen — confirm game resumes from the correct port with correct cash/cargo/debt.
3. Play to game-over (sunk). Reopen — confirm game-over screen is shown (data was saved).
4. Click Restart — confirm fresh game starts, `seenTutorial` is already true (no repeat tutorial).
5. Open on a phone-sized window — confirm all buttons are reachable without mis-taps.

---

## Out of Scope

- DataStore migrations (no schema changes planned before Phase 8)
- Leaderboard UI (score is saved but display is Phase 8 territory)
- Sound effects, particle effects, 3D elements
- Multi-player (game is single-player throughout)
