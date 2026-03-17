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

### Modified file
`src/ReplicatedStorage/shared/GameState.lua` — add `seenTutorial = false` to the state table returned by `newGame`. This makes `seenTutorial` a first-class field with a defined default, consistent with all other state fields.

### Canonical fields (saved to DataStore)

```
startChoice, cash, debt, bankBalance,
shipCapacity, shipCargo[1..4], guns, damage, pirateBase,
warehouseCargo[1..4], basePrices,
currentPort, month, year, turnsElapsed,
liYuenProtection, wuWarningGiven, bankruptcyCount,
enemyBaseDamage, enemyBaseHP,
gameOver, gameOverReason, finalScore, finalRating,
seenTutorial
```

### Derived on load (not saved)

Computed fields (recalculated from canonical data):

| Field | How derived |
|---|---|
| `holdSpace` | `shipCapacity - Σshipcargo - guns×10` — `shipCapacity` includes upgrades; `shipCargo` values reflect in-port trading before disconnect |
| `warehouseUsed` | `Σwarehousecargo` |
| `currentPrices` | `PriceEngine.calculatePrices(basePrices, currentPort)` — uses the restored (drifted) `basePrices` |
| `destination` | Set to `currentPort` |

Ephemeral fields reset to defaults on load:

| Field | Value on load | Notes |
|---|---|---|
| `liYuenOfferCost` | `nil` | Recalculated on next HK arrival |
| `inWuSession` | `false` | Any Wu/bank/warehouse actions taken after the last departure but before disconnect are not replayed (see Known Limitations) |
| `pendingTutorial` | `nil` | Only set on fresh games via `ChooseStart` |
| `combat` | `nil` | Player resumes at port with no active combat |
| `shipOffer` | `nil` | Regenerated on next HK arrival |

### Schema

Saved table includes `version = 1` for future migration support.

### Functions

**`PersistenceEngine.serialize(state)`**
Returns a plain table containing all canonical fields plus `version = 1`. Does not mutate `state`.

**`PersistenceEngine.deserialize(data, PriceEngine)`**
Takes a saved data table and `PriceEngine` (dependency injection for testability). Constructs and returns a complete state table directly from `data` — `GameState.newGame` is **not** called. All canonical fields are copied from `data` (including `startChoice`, which is stored as a raw field). Derived fields are then populated: `basePrices` is copied first so `PriceEngine.calculatePrices` uses the correct (drifted) matrix; `holdSpace` is computed from the restored `shipCargo` values (which reflect any in-port trading before disconnect). Ephemeral fields are set to their reset defaults (see Derived on load table). If `data.seenTutorial` is absent (save from an older build), defaults to `false`. Returns `nil` if `data` is nil or `data.version` is missing or unrecognised.

**`PersistenceEngine.dataStoreRetry(fn, maxAttempts)`**
Calls `fn()` up to `maxAttempts` times (default 3). After each failure *except the last*, waits before retrying: 1s after attempt 1, 2s after attempt 2 (no wait after the final failed attempt). Uses `task.wait()` (not the deprecated `wait()`). Returns the result on success, or `nil` after all attempts are exhausted. Errors are caught with `pcall`; each failure is logged via `warn()`. With 3 attempts the maximum total backoff is 3s (1+2).

### Tests
`tests/PersistenceEngine.spec.lua` — covers:
- `serialize` produces a table with `version = 1`
- `serialize` includes all canonical fields (including `pirateBase`, `wuWarningGiven`, `bankruptcyCount`)
- `deserialize` restores all canonical fields
- `deserialize` computes derived fields correctly (`holdSpace`, `warehouseUsed`, `destination`, `currentPrices` is not nil)
- `deserialize` sets ephemeral fields to correct defaults (`combat = nil`, `shipOffer = nil`, `inWuSession = false`)
- `deserialize` returns `nil` for nil input
- `deserialize` returns `nil` for data with missing `version`
- `dataStoreRetry` returns result on first-call success
- `dataStoreRetry` retries on failure and returns result on a later successful attempt
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

### `pushState` helper (modified)

The existing guard `if state then` must be tightened to `if type(state) == "table"` to prevent sending the sentinel `true` value to the client during the async load window:

```lua
local function pushState(player)
  local state = playerStates[player]
  if type(state) == "table" then  -- guard against sentinel during async load
    Remotes.StateUpdate:FireClient(player, state)
  end
end
```

### `ChooseStart` handler (modified)

The existing `if playerStates[player] then return end` guard must be extended to prevent a second `ChooseStart` firing while the first is yielding on DataStore. Set a sentinel immediately, before any yield point:

```lua
if playerStates[player] then return end
playerStates[player] = true  -- sentinel: claim slot before async load
local loaded = loadPlayer(player)  -- yields here
if loaded then
  -- Loaded save: gameOver may be true (show game-over screen), or false (resume play)
  playerStates[player] = loaded
  pushState(player)
  return
end
-- No save: fresh game
local state = GameState.newGame(startChoice)
-- ... initialise prices, holdSpace as before ...
-- state.seenTutorial is already false (set by GameState.newGame)
state.pendingTutorial = true  -- fires tutorial on first HK arrival
playerStates[player] = state
pushState(player)
```

**Note on game-over saves:** If `loaded.gameOver == true`, push state directly — the client will display the game-over screen. The player can then click Restart to begin a new game.

### `TravelTo` handler (modified)

**Onboarding check** — add before `pushState`, when `destination == Constants.HONG_KONG` and `state.pendingTutorial`:

```lua
if destination == Constants.HONG_KONG and state.pendingTutorial then
  state.pendingTutorial = nil
  Remotes.Notify:FireClient(player, "Welcome, Taipan! Visit Elder Brother Wu to borrow cash or repay your debt.")
  Remotes.Notify:FireClient(player, "Use the Warehouse to store goods safely between voyages — holds up to 10,000 units.")
  Remotes.Notify:FireClient(player, "Li Yuen commands the seas. Pay for his protection in Hong Kong to avoid his fleet.")
  state.seenTutorial = true
  savePlayer(player, state)  -- persist immediately so tutorial never repeats
end
```

**Save on departure** — call `savePlayer(player, state)` after the final `pushState(player)` call at the end of the `TravelTo` handler (not after any intermediate `pushState` calls inside sub-helpers like `postCombatStorm`). On a new player's first travel to HK, both the tutorial save (above) and the departure save will fire in the same handler invocation — this double-save is harmless and expected.

### `RestartGame` handler (modified)

Carry `seenTutorial` forward so the tutorial does not replay after restart:

```lua
Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or not state.gameOver then return end
  local wasTutorialSeen = state.seenTutorial  -- preserve across restart
  local newState = GameState.newGame("cash")
  -- ... initialise prices, holdSpace as before ...
  newState.seenTutorial = wasTutorialSeen
  if not wasTutorialSeen then
    newState.pendingTutorial = true  -- tutorial still pending; will fire on first HK arrival
  end
  playerStates[player] = newState
  pushState(player)
end)
```

### `Players.PlayerRemoving` (modified)

- Call `savePlayer(player, state)` before `playerStates[player] = nil`

### `game:BindToClose()` (new)

```lua
game:BindToClose(function()
  for player, state in pairs(playerStates) do
    if type(state) == "table" then  -- skip sentinel "true" values
      savePlayer(player, state)
      -- DataStore calls yield the coroutine; each save completes before the next begins.
      -- With 3 retry attempts (max 3s backoff per save) and single-player, well within 30s budget.
    end
  end
end)
```

---

## Task 3: UI Polish Pass

### Mobile — 44px touch target floor

All `TextButton` and `TextBox` instances must meet a 44px minimum height. Existing buttons at 28px are raised; newly-created panels (added in Phases 3–5) must also be verified and corrected. Downstream panel heights and position cascades are adjusted as needed.

| Panel | Elements affected |
|---|---|
| `BuySellPanel.lua` | Buy, Sell, End Turn buttons; quantity input box |
| `WarehousePanel.lua` | Transfer To/From buttons; quantity input box |
| `WuPanel.lua` | Repay, Borrow, Leave, Protection buttons; amount input box |
| `BankPanel.lua` | Deposit, Withdraw buttons; amount input box |
| `ShipPanel.lua` | Repair, All, Done buttons; amount input box; Accept/Decline pairs |
| `CombatPanel.lua` | Fight, Run, Throw buttons; quantity input box |
| `GameOverPanel.lua` | Restart button |
| `PortPanel.lua` | Retire, Quit buttons (port travel buttons already 50px — no change) |

### Colour audit — enforce palette

| Role | RGB | Applied to |
|---|---|---|
| Amber | `(200, 180, 80)` | Titles, labels, data values, date display |
| Green | `(140, 200, 80)` | Action buttons, port names, positive outcomes |
| Red | `(220, 80, 80)` | Quit, game-over, sunk state |
| Orange | `(220, 120, 60)` | Repair/damage (warning tone) |
| Blue | `(120, 120, 220)` | Gun purchase (distinct action type) |
| Grey | `(80, 80, 80)` | Disabled elements, current port button |

Any button or label using an ad-hoc colour is moved to the nearest palette entry. No new layout or spacing changes beyond what the mobile pass requires.

### No automated tests for Task 3

Visual verification via Studio injection and manual review.

---

## Milestone Test

1. Play a game, travel to several ports, then force-quit Roblox.
2. Reopen — confirm game resumes from the correct port with correct cash/cargo/debt.
3. Play to game-over (sunk). Reopen — confirm game-over screen is shown (data was saved).
4. Click Restart — confirm fresh game starts, tutorial does not repeat (`seenTutorial` carried forward).
5. Open on a phone-sized window — confirm all buttons are reachable without mis-taps.

---

## Known Limitations

**Mid-HK-session data loss:** State is saved on port departure and on `PlayerRemoving`. A player who arrives at HK, performs Wu/bank/warehouse actions, then disconnects without departing will have those in-session transactions lost — the restored save reflects state at the previous departure. This is an acceptable trade-off for Phase 7 (saving after every action would approach DataStore rate limits). Acknowledged here so testers know this scenario is not a bug.

---

## Out of Scope

- DataStore migrations (no schema changes planned before Phase 8)
- Leaderboard UI (score is saved but display is Phase 8 territory)
- Sound effects, particle effects, 3D elements
- Multi-player (game is single-player throughout)
