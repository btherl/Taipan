# CLAUDE.md — Taipan! Roblox Project

## Project Overview

Taipan! is a single-player Roblox port of the classic 1982 Apple II trading game. The player is a merchant sailing the South China Sea in the 1860s, trading goods (Opium, Silk, Arms, General Cargo) between 7 ports, managing debt with Elder Brother Wu, fighting pirates, and trying to amass enough wealth to retire. The game is pure 2D ScreenGui — no 3D world.

The original BASIC source is annotated in `BASIC_ANNOTATED.md`; all formulas cite BASIC line numbers. The authoritative game design is in `DESIGN_DOCUMENT.md`.

## Tech Stack

- **Roblox** (Luau) — game runtime
- **Rojo** — file-based source control; `default.project.json` maps `src/` to Roblox services
- **TestEZ** — unit testing framework (bundled at `src/ReplicatedStorage/TestEZ.lua`)
- **MCP Studio integration** — Roblox Studio MCP tools for runtime code injection and play-testing
- **DataStore** — player persistence via `DataStoreService` (store name: `TaipanV1`)

## Critical Workflow: Rojo Does NOT Auto-Sync

**Rojo does NOT automatically push file changes into Studio.** When you edit a file on disk, you MUST also patch it into Studio via the MCP `run_code` tool. The typical workflow is:

1. Edit the `.lua` file on disk (for git).
2. Use `mcp__Roblox_Studio__run_code` to inject the same change into the running Studio session.
3. Test in Studio.

If you only edit on disk, Studio will have stale code until the next Rojo sync or manual injection.

## Architecture

### Server-Authoritative Model

All game logic runs on the server (`GameService.server.lua`). The client is pure UI — it receives state snapshots and sends action requests. The client never computes game state.

```
Client (StarterGui)                    Server (ServerScriptService)
  StartPanel → ChooseStart ──────────→ GameService
  BuySellPanel → BuyGoods/SellGoods ─→ validates + mutates state
  PortPanel → TravelTo ──────────────→ time advance + events + combat
  WuPanel → WuRepay/WuBorrow/LeaveWu → finance mutations
  BankPanel → BankDeposit/Withdraw ──→ bank mutations
  CombatPanel → CombatFight/Run/Throw → combat resolution
  ShipPanel → ShipRepair/AcceptUpgrade/AcceptGun → progression
                                         ↓
                              StateUpdate (full snapshot)
                              Notify (message strings)
                                         ↓
                              Client updates ALL panels
```

### State Flow

1. Server holds `playerStates[player]` — one state table per connected player.
2. Every mutation ends with `pushState(player)` which fires `Remotes.StateUpdate:FireClient(player, state)`.
3. The client's `init.client.lua` receives the state and calls `.update(state)` on every panel.
4. Server notifications (Wu warnings, combat messages, etc.) go via `Remotes.Notify` and display in `MessagePanel`.

### Sentinel Pattern for Async Load

When `ChooseStart` fires, the server sets `playerStates[player] = true` (a boolean sentinel) before the DataStore yield. All handlers guard with `if type(state) ~= "table" then return end`, so requests during load are silently dropped. After load completes, the sentinel is replaced with the real state table.

## File Structure

```
D:/dev/taipan/
├── default.project.json          # Rojo project config
├── CLAUDE.md                     # This file
├── DESIGN_DOCUMENT.md            # Authoritative game design (v3.0)
├── BASIC_ANNOTATED.md            # Annotated Apple II BASIC source
│
├── src/
│   ├── ServerScriptService/
│   │   └── GameService.server.lua    # THE server — all state mutations happen here
│   │
│   ├── ReplicatedStorage/
│   │   ├── Remotes.lua               # All RemoteEvents (single source of truth)
│   │   ├── TestEZ.lua                # TestEZ framework module
│   │   ├── Text/                     # Custom font rendering (BMFont-based)
│   │   │   ├── init.lua
│   │   │   ├── lib/ (Signal, TextSprite, Unicode, Util, XMLParser)
│   │   │   └── Fonts/November/FontData.lua
│   │   └── shared/                   # Pure logic modules (no Roblox service calls)
│   │       ├── Constants.lua         # All fixed game data — edit here to tune balance
│   │       ├── GameState.lua         # newGame(startChoice) constructor
│   │       ├── PriceEngine.lua       # Price calculation, crash/boom, annual drift
│   │       ├── Validators.lua        # canBuy(), canSell() guards
│   │       ├── TravelEngine.lua      # Time advance, departure validation
│   │       ├── FinanceEngine.lua     # Wu repay/borrow/bankruptcy, bank, Li Yuen
│   │       ├── EventEngine.lua       # Opium seizure, cargo theft, robbery, storm
│   │       ├── CombatEngine.lua      # Encounter checks, fight/run/throw, enemy fire
│   │       ├── ProgressionEngine.lua # Repair, upgrade, guns, score, rating, retirement
│   │       └── PersistenceEngine.lua # Serialize/deserialize state, DataStore retry
│   │
│   └── StarterGui/
│       └── TaipanGui/
│           ├── init.client.lua       # GameController — wires panels to Remotes
│           └── Panels/
│               ├── StartPanel.lua      # Start choice (cash/guns), ZIndex=30
│               ├── PortPanel.lua       # Port name, date, travel buttons, RETIRE/QUIT
│               ├── StatusStrip.lua     # Cash | Debt | Bank | Guns one-liner
│               ├── InventoryPanel.lua  # Hold + warehouse cargo side by side
│               ├── PricesPanel.lua     # Current 4-good price table
│               ├── BuySellPanel.lua    # Good selector, amount input, Buy/Sell/End Turn
│               ├── WarehousePanel.lua  # Transfer goods (HK only)
│               ├── WuPanel.lua         # Repay/borrow/Li Yuen protection (HK only)
│               ├── BankPanel.lua       # Deposit/withdraw (HK only)
│               ├── MessagePanel.lua    # Floating notification bar, ZIndex=10
│               ├── ShipPanel.lua       # Repair/upgrade/gun offers modal (HK), ZIndex=12
│               ├── CombatPanel.lua     # Combat overlay, ZIndex=15
│               └── GameOverPanel.lua   # Full-screen game-over overlay, ZIndex=20
│
├── tests/
│   ├── TestRunner.server.lua         # Discovers and runs all .spec files
│   ├── Constants.spec.lua
│   ├── GameState.spec.lua
│   ├── PriceEngine.spec.lua
│   ├── Validators.spec.lua
│   ├── TravelEngine.spec.lua
│   ├── FinanceEngine.spec.lua
│   ├── EventEngine.spec.lua
│   ├── CombatEngine.spec.lua
│   ├── ProgressionEngine.spec.lua
│   └── PersistenceEngine.spec.lua
│
└── docs/superpowers/
    ├── plans/                        # Implementation plans (per phase)
    └── specs/                        # Design specs
```

### Rojo Mapping (default.project.json)

| Disk Path | Roblox Location |
|---|---|
| `src/ServerScriptService/` | `ServerScriptService` |
| `tests/` | `ServerScriptService.Tests` (Folder) |
| `src/ReplicatedStorage/` | `ReplicatedStorage` |
| `src/StarterGui/TaipanGui/` | `StarterGui.TaipanGui` (ScreenGui) |

## Game State

The canonical state table is created by `GameState.newGame(startChoice)`. Key fields:

### Economy
| Field | BASIC var | Description |
|---|---|---|
| `cash` | CA | Player's current cash |
| `bankBalance` | BA | Bank savings (earns 0.5%/month interest) |
| `debt` | DW | Debt to Elder Brother Wu (10%/month compound) |

### Ship
| Field | BASIC var | Description |
|---|---|---|
| `shipCapacity` | SC | Total hold capacity (starts 60, +50 per upgrade) |
| `holdSpace` | MW | **Derived**: `shipCapacity - sum(shipCargo) - guns*10` |
| `damage` | DM | Ship damage (may be fractional during combat) |
| `guns` | GN | Number of cannons (each uses 10 hold space) |

### Cargo
| Field | Description |
|---|---|
| `shipCargo[1..4]` | Goods on ship: 1=Opium, 2=Silk, 3=Arms, 4=General |
| `warehouseCargo[1..4]` | Goods in Hong Kong warehouse |
| `warehouseUsed` | **Derived**: `sum(warehouseCargo)` |

### Prices
| Field | Description |
|---|---|
| `currentPrices[1..4]` | Current port prices (recalculated on arrival) |
| `basePrices[port][good]` | Mutable 7x4 matrix (drifts +0/1 each January) |

### Time & Location
| Field | BASIC var | Description |
|---|---|---|
| `turnsElapsed` | TI | Starts at 1, increments each voyage |
| `month` | MO | 1-12 |
| `year` | YE | Starts 1860 |
| `currentPort` | LO | 1-7 (index into Constants.PORT_NAMES) |
| `destination` | D | 0 at game start, then 1-7 |

### Combat Scaling (increase each January)
| Field | BASIC var | Start | Annual Increment |
|---|---|---|---|
| `enemyBaseHP` | EC | 20 | +10 |
| `enemyBaseDamage` | ED | 0.5 | +0.5 |
| `pirateBase` | BP | 10 (cash) / 7 (guns) | — |

### Flags & Progression
| Field | Description |
|---|---|
| `wuWarningGiven` | Bool: Wu's braves warning (fires once) |
| `liYuenProtection` | 0=unprotected, 1=protected (lapses 1-in-20 per voyage) |
| `liYuenOfferCost` | Ephemeral: cost for Li Yuen protection at HK |
| `inWuSession` | Bool: currently in Wu interaction at HK |
| `bankruptcyCount` | Emergency loan counter (escalates repayment) |
| `gameOver` | Bool: game has ended |
| `gameOverReason` | `"sunk"` / `"quit"` / `"retired"` / nil |
| `finalScore` / `finalRating` | Set at game over |
| `shipOffer` | Ephemeral: `{repairRate, upgradeOffer, gunOffer}` at HK |
| `combat` | Sub-table during combat, nil otherwise |
| `startChoice` | `"cash"` or `"guns"` (persisted for save/load) |
| `seenTutorial` | Bool: onboarding tutorial shown |

### Canonical vs Derived Fields

**Canonical** (persisted): cash, debt, bankBalance, shipCapacity, guns, damage, shipCargo, warehouseCargo, basePrices, currentPort, month, year, turnsElapsed, pirateBase, liYuenProtection, wuWarningGiven, bankruptcyCount, enemyBaseHP, enemyBaseDamage, gameOver, gameOverReason, finalScore, finalRating, startChoice, seenTutorial.

**Derived** (recomputed on load/arrival): holdSpace, warehouseUsed, currentPrices, destination.

**Ephemeral** (not persisted): combat, shipOffer, liYuenOfferCost, inWuSession, pendingTutorial.

## Engine Modules

All engine modules are in `src/ReplicatedStorage/shared/`. They are **pure logic** — no Roblox service calls, no yields, no state creation. They take a state table and mutate it or return values.

| Module | Purpose |
|---|---|
| `Constants.lua` | All fixed game data: port names, good names, base prices, start values, rates |
| `GameState.lua` | `newGame(startChoice)` — creates a fresh state table |
| `PriceEngine.lua` | `calculatePrices(basePrices, port)` — random prices with crash/boom; `applyAnnualDrift(basePrices)` |
| `Validators.lua` | `canBuy()`, `canSell()`, `holdSpaceFor()` — pure validation |
| `TravelEngine.lua` | `timeAdvance(state)` — month/year/interest; `canDepart(state, dest)` |
| `FinanceEngine.lua` | Wu repay/borrow/bankruptcy, bank deposit/withdraw, Li Yuen protection |
| `EventEngine.lua` | Opium seizure, cargo theft, cash robbery, storm (occurs/severity/sinks/blown off course) |
| `CombatEngine.lua` | Encounter checks, fleet sizing, initCombat, fight/run/throw, enemy fire, booty |
| `ProgressionEngine.lua` | Repair, upgrade/gun offers, score, rating, retirement eligibility |
| `PersistenceEngine.lua` | Serialize/deserialize for DataStore, retry with exponential backoff |

### FN_R Helper Pattern

Many modules use this BASIC-faithful random helper:
```lua
local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end
```
This replicates `FN R(X) = INT(RND(1)*X)` from the original BASIC.

## Testing

### How to Run Tests

Tests run in **Studio Run mode** only (not Play mode, not live servers). The guard is:
```lua
if not RunService:IsRunMode() then return end
```

To run tests:
1. Open Roblox Studio with the Taipan place.
2. Click the **Run** button (not Play/Play Here).
3. `TestRunner.server.lua` auto-discovers all `.spec.lua` files in `ServerScriptService.Tests` and runs them via TestEZ.
4. Output appears in the Studio Output panel.

### Test File Convention

- Spec files live in `tests/` and are named `<ModuleName>.spec.lua`.
- Each spec file returns a function containing `describe`/`it`/`expect` blocks (TestEZ style).
- Tests require modules via `game:GetService("ReplicatedStorage").shared.<ModuleName>`.

### Writing New Tests

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MyEngine = require(ReplicatedStorage.shared.MyEngine)

return function()
  describe("MyEngine.someFunction", function()
    it("does the expected thing", function()
      local result = MyEngine.someFunction(input)
      expect(result).to.equal(expectedValue)
    end)
  end)
end
```

## MCP UI Playtesting

Claude can drive the game UI end-to-end using the Roblox Studio MCP tools. This complements the TestEZ unit tests (which test pure logic modules in isolation) — MCP playtesting verifies that the UI correctly wires into the game logic at runtime.

### MCP Tools and Their Roles

| Tool | Purpose |
|---|---|
| `start_stop_play` | Enter/exit Play mode (`is_start: true/false`) |
| `screen_capture` | Capture current Studio viewport; use after every action to observe UI state |
| `user_mouse_input` | Click GUI elements using pixel coordinates derived from `inspect_instance` |
| `user_keyboard_input` | Send key presses; preferred for the Apple II interface (fully keyboard-driven) |
| `search_game_tree` + `inspect_instance` | Discover runtime GUI hierarchy under `Players.LocalPlayer.PlayerGui` and read properties (Text, Visibility, AbsolutePosition, AbsoluteSize) |
| `execute_luau` | Runs **client-side** Luau; used to fire remotes and capture state |

### Critical: execute_luau Runs Client-Side

Despite intuition, `execute_luau` executes in the **client context** during Play mode. ServerScriptService scripts are consumed by Rojo and not directly accessible. This means:

- **Can** fire `RemoteEvent:FireServer()` to simulate client actions
- **Can** connect `RemoteEvent.OnClientEvent` to capture server responses
- **Cannot** directly read server-side local variables (e.g. `playerStates`)

### State Verification Pattern

To read current game state, fire `RequestStateUpdate` and capture the `StateUpdate` response:

```lua
local Remotes = require(game:GetService("ReplicatedStorage").Remotes)
local state = nil
Remotes.StateUpdate.OnClientEvent:Connect(function(s) state = s end)
Remotes.RequestStateUpdate:FireServer()
-- (wait a tick, then read state)
```

### GUI Element Discovery Pattern

Runtime GUI elements (created programmatically by panels) only exist under `LocalPlayer.PlayerGui` during Play mode. Use `search_game_tree` to find them, then `inspect_instance` to get coordinates:

```
instance path: Players.LocalPlayer.PlayerGui.TaipanGui.Root.<PanelName>.<ElementName>
```

Compute click target from properties: `AbsolutePosition + AbsoluteSize / 2`.

### Recommended Playtest Sequence

1. `start_stop_play(true)` — enter Play mode
2. `screen_capture` — observe starting state
3. Interact via `user_keyboard_input` (Apple II interface) or `user_mouse_input` (GUI buttons)
4. `screen_capture` — verify UI changed as expected
5. Fire `RequestStateUpdate` via `execute_luau`, capture `StateUpdate` response — verify server state
6. Repeat steps 3-5 for each action under test
7. `start_stop_play(false)` — exit Play mode when done

### Proof-of-Concept Results

The full flow was tested successfully end-to-end:

1. Started Play mode
2. Selected Apple II interface (mouse click on InterfacePicker button)
3. Selected "Firm" cash start (keypress `F` on Apple II terminal screen)
4. Verified server state: `currentPort=1`, `cash=400`, `debt=5000`, `guns=0`, `year=1860`, `gameOver=false`

## Constants Reference

Key constants from `src/ReplicatedStorage/shared/Constants.lua`:

| Constant | Value | Notes |
|---|---|---|
| `PORT_NAMES` | 7 ports (HK, Shanghai, Nagasaki, Saigon, Manila, Singapore, Batavia) | Index 1-7 |
| `HONG_KONG` | 1 | Port index for HK-only events |
| `GOOD_NAMES` | Opium, Silk, Arms, General Cargo | Index 1-4 |
| `PRICE_SCALE` | {1000, 100, 10, 1} | Opium most valuable |
| `BASE_PRICES[port][good]` | 7x4 matrix | From BASIC line 10200 |
| `WAREHOUSE_CAPACITY` | 10000 | Fixed, not per-player |
| `CASH_START_*` | cash=400, debt=5000, hold=60, guns=0, BP=10 | Firm start |
| `GUNS_START_*` | cash=0, debt=0, hold=60, guns=5, BP=7 | Ship start |
| `BANK_INTEREST_RATE` | 0.005 (0.5%/month) | Applied each voyage |
| `DEBT_INTEREST_RATE` | 0.1 (10%/month) | Compound, applied each voyage |
| `EC_START` / `ED_START` | 20 / 0.5 | Enemy HP/damage base, +10/+0.5 per year |

## GUI System

### Panel Layout

The UI is a 480px-wide vertical column (`Root` frame). Panels are stacked by absolute Y positions:

| Panel | Y Position | Height | Visibility |
|---|---|---|---|
| PortPanel | 0 | 140px | Always |
| StatusStrip | 125 | 30px | Always |
| InventoryPanel | 160 | 120px | Always |
| PricesPanel | 285 | 120px | Always |
| BuySellPanel | 410 | 155px | Always |
| WarehousePanel | 615 | 178px | HK only |
| WuPanel | 780 | 280px | HK only |
| BankPanel | 1010 | 128px | HK only |

### Overlay Panels (ZIndex layering)

| Panel | ZIndex | Trigger |
|---|---|---|
| MessagePanel | 10 | `Remotes.Notify` (auto-hides after 5s) |
| ShipPanel | 12 | `state.shipOffer ~= nil` at HK |
| CombatPanel | 15 | `state.combat ~= nil` |
| GameOverPanel | 20 | `state.gameOver == true` |
| StartPanel | 30 | Initial load (destroyed after first StateUpdate) |

### Panel Update Pattern

Every panel exposes `.update(state)` and optionally `.show(message)` (MessagePanel only). The client controller calls all panel updates on every `StateUpdate` event. Panels self-manage visibility based on state (e.g., WarehousePanel checks `state.currentPort == Constants.HONG_KONG`).

### "A" = All Shortcut

Many input panels support typing "A" in the amount box to mean "all available" (e.g., all cash, all cargo). Each panel stores `latestState` on every update to resolve "A" at click time.

## Coding Conventions

1. **Pure logic modules** in `shared/` — no `game:GetService()` calls (except `require(script.Parent...)`), no yields, no Instance creation. This makes them testable.
2. **Server-only mutation** — all state changes happen in `GameService.server.lua`. Client panels are read-only displays.
3. **Every handler ends with `pushState(player)`** — ensures the client always has the latest state.
4. **Guard pattern** — every remote handler starts with: `local state = playerStates[player]; if type(state) ~= "table" then return end`
5. **Input validation** — server validates all client inputs (goodIndex 1-4, positive integer quantities, port 1-7) before any mutation.
6. **BASIC fidelity** — formulas match the original BASIC with line-number citations in comments.
7. **Colour palette**: Amber (`200,180,80`) for labels/info, Green (`140,200,80`) for positive actions, Red (`220,80,80`) for negative/danger, Orange (`220,120,60`) for secondary actions, DIM (`80,80,80`) for disabled.
8. **Font**: `Enum.Font.RobotoMono` throughout (monospace terminal aesthetic).
9. **Touch targets**: Minimum 44px height for all interactive buttons (mobile-friendly).
10. **Panel constructor pattern**: `PanelName.new(parent, ...callbacks)` returns a table with `.update(state)`.

## Remotes Reference

All RemoteEvents are defined in `src/ReplicatedStorage/Remotes.lua`. Key remotes:

**Client to Server:**
- `ChooseStart` — "cash" or "guns"
- `BuyGoods` / `SellGoods` — goodIndex, quantity
- `TravelTo` — destination (1-7)
- `TransferToWarehouse` / `TransferFromWarehouse` — goodIndex, quantity
- `WuRepay` / `WuBorrow` — amount
- `LeaveWu` — triggers enforcer check
- `BankDeposit` / `BankWithdraw` — amount
- `BuyLiYuenProtection` — no args
- `CombatFight` / `CombatRun` / `CombatThrow` — (throw: goodIndex, qty)
- `ShipRepair` — amount (cash to spend)
- `AcceptUpgrade` / `DeclineUpgrade` / `AcceptGun` / `DeclineGun` / `ShipPanelDone`
- `Retire` / `QuitGame`
- `EndTurn` — recalculate prices
- `RequestStateUpdate` — client requests full refresh
- `RestartGame` — restart after game over

**Server to Client:**
- `StateUpdate` — full state snapshot
- `Notify` — message string

## Development Phases (Status)

| Phase | Description | Status |
|---|---|---|
| 1 | Foundation + Trading Loop | Complete |
| 2 | Travel + All Ports + Time | Complete |
| 3 | Financial System (Wu + Bank + Li Yuen) | Complete |
| 4 | Random Events + Storm | Complete |
| 5 | Combat | Complete |
| 6 | Ship Progression + Score + Retirement | Complete |
| 7 | Persistence + Polish (DataStore, onboarding, UI) | Complete |
| 8 | Custom fonts (BMFont XML generator) | In progress |

Plans are in `docs/superpowers/plans/`. Design specs are in `docs/superpowers/specs/`.

## Key Game Mechanics Summary

- **Ports**: 7 ports, Hong Kong is special (warehouse, Wu, bank, ship offers).
- **Trading**: Buy/sell 4 goods; prices = `basePrices[port][good] / 2 * random(1-3) * PRICE_SCALE[good]`; 1-in-9 crash/boom per visit.
- **Time**: 1 month per voyage. January triggers: year rollover, base price drift (+0/1 per cell), combat scaling (+10 HP, +0.5 damage).
- **Finance**: Wu lends at 10%/month compound. Bank pays 0.5%/month. Bankruptcy gives emergency loan with escalating repayment.
- **Combat**: Pirates encounter based on `1/pirateBase` chance. 10-slot grid, fight/run/throw actions. Booty on victory. Post-combat storm possible.
- **Progression**: Ship upgrade (+50 capacity), gun purchase (costs 10 hold), repair. Score = `netWorth / 100 / turnsElapsed^1.1`. Retire at net worth >= $1,000,000.
- **Persistence**: DataStore `TaipanV1`, key `player_<UserId>`. Saves on every departure and disconnect. Retry with exponential backoff (1s, 2s, 4s).
