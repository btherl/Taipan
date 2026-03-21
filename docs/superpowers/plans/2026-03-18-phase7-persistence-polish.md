# Phase 7: Persistence + Polish — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add DataStore persistence (player progress survives disconnects), DataStore-gated first-play onboarding, and a UI polish pass (44px mobile touch targets + colour palette audit).

**Architecture:** New `PersistenceEngine` pure-logic module handles serialise/deserialise/retry. `GameService` gains DataStore helpers and a sentinel-based async load pattern. All 8 UI panels get their buttons raised to ≥44px and colours audited against the spec palette.

**Tech Stack:** Luau, Roblox DataStore API, TestEZ (tests run in Studio edit mode), Rojo (disk → Studio sync), Roblox Studio MCP injection.

**Reference spec:** `docs/superpowers/specs/2026-03-18-phase7-persistence-polish-design.md`

---

## File Map

| Action | File |
|---|---|
| Create | `src/ReplicatedStorage/shared/PersistenceEngine.lua` |
| Create | `tests/PersistenceEngine.spec.lua` |
| Modify | `src/ReplicatedStorage/shared/GameState.lua` |
| Modify | `src/ServerScriptService/GameService.server.lua` |
| Modify | `src/StarterGui/TaipanGui/Panels/BuySellPanel.lua` |
| Modify | `src/StarterGui/TaipanGui/Panels/WarehousePanel.lua` |
| Modify | `src/StarterGui/TaipanGui/Panels/WuPanel.lua` |
| Modify | `src/StarterGui/TaipanGui/Panels/BankPanel.lua` |
| Modify | `src/StarterGui/TaipanGui/Panels/ShipPanel.lua` |
| Modify | `src/StarterGui/TaipanGui/Panels/CombatPanel.lua` |
| Modify | `src/StarterGui/TaipanGui/Panels/GameOverPanel.lua` |
| Modify | `src/StarterGui/TaipanGui/Panels/PortPanel.lua` |

---

## Chunk 1: PersistenceEngine — pure logic + tests

### Task 1: PersistenceEngine.lua + spec + GameState tweak

**Files:**
- Create: `src/ReplicatedStorage/shared/PersistenceEngine.lua`
- Create: `tests/PersistenceEngine.spec.lua`
- Modify: `src/ReplicatedStorage/shared/GameState.lua`

---

- [ ] **Step 1.1: Add `startChoice` and `seenTutorial` to GameState.newGame**

Open `src/ReplicatedStorage/shared/GameState.lua`. In `GameState.newGame`, find the `-- Flags` block (around line 62) and add two fields:

```lua
    -- Flags
    wuWarningGiven   = false,
    liYuenProtection = 0,
    liYuenOfferCost  = nil,
    inWuSession      = false,
    bankruptcyCount  = 0,
    gameOver         = false,
    combat           = nil,
    startChoice      = startChoice,   -- ADD: raw start type for save/load round-trips
    seenTutorial     = false,         -- ADD: set true after first HK tutorial fires
```

---

- [ ] **Step 1.2: Write the failing tests**

Create `tests/PersistenceEngine.spec.lua`:

```lua
-- PersistenceEngine.spec.lua
return function()
  local RS = game:GetService("ReplicatedStorage")
  local PE = require(RS.shared.PersistenceEngine)
  local PriceEngine = require(RS.shared.PriceEngine)

  local function makeState(overrides)
    local s = {
      startChoice      = "cash",
      cash             = 10000,
      debt             = 5000,
      bankBalance      = 2000,
      shipCapacity     = 60,
      shipCargo        = {10, 5, 0, 0},
      guns             = 2,
      damage           = 10,
      pirateBase       = 10,
      warehouseCargo   = {20, 0, 0, 0},
      basePrices       = (function()
        local bp = {}
        for p = 1, 7 do
          bp[p] = {}
          for g = 1, 4 do bp[p][g] = p * 10 + g end
        end
        return bp
      end)(),
      currentPort      = 3,
      month            = 6,
      year             = 1862,
      turnsElapsed     = 5,
      liYuenProtection = 0,
      wuWarningGiven   = true,
      bankruptcyCount  = 1,
      enemyBaseDamage  = 11,
      enemyBaseHP      = 20,
      gameOver         = false,
      gameOverReason   = nil,
      finalScore       = nil,
      finalRating      = nil,
      seenTutorial     = true,
    }
    if overrides then
      for k, v in pairs(overrides) do s[k] = v end
    end
    return s
  end

  describe("serialize", function()
    it("includes version = 1", function()
      expect(PE.serialize(makeState()).version).to.equal(1)
    end)

    it("includes all canonical fields including pirateBase, wuWarningGiven, bankruptcyCount", function()
      local data = PE.serialize(makeState())
      expect(data.startChoice).to.equal("cash")
      expect(data.pirateBase).to.equal(10)
      expect(data.wuWarningGiven).to.equal(true)
      expect(data.bankruptcyCount).to.equal(1)
      expect(data.seenTutorial).to.equal(true)
      expect(data.shipCargo[1]).to.equal(10)
      expect(data.warehouseCargo[1]).to.equal(20)
      expect(data.basePrices[1][1]).to.equal(11)
    end)

    it("does not mutate state (version not added to original)", function()
      local s = makeState()
      PE.serialize(s)
      expect(s.version).to.equal(nil)
    end)

    it("does not include computed fields", function()
      local data = PE.serialize(makeState())
      expect(data.holdSpace).to.equal(nil)
      expect(data.warehouseUsed).to.equal(nil)
      expect(data.currentPrices).to.equal(nil)
      expect(data.combat).to.equal(nil)
    end)
  end)

  describe("deserialize", function()
    it("returns nil for nil input", function()
      expect(PE.deserialize(nil, PriceEngine)).to.equal(nil)
    end)

    it("returns nil for data with missing version", function()
      local data = PE.serialize(makeState())
      data.version = nil
      expect(PE.deserialize(data, PriceEngine)).to.equal(nil)
    end)

    it("restores all canonical fields", function()
      local s = makeState()
      local restored = PE.deserialize(PE.serialize(s), PriceEngine)
      expect(restored.cash).to.equal(10000)
      expect(restored.startChoice).to.equal("cash")
      expect(restored.pirateBase).to.equal(10)
      expect(restored.wuWarningGiven).to.equal(true)
      expect(restored.bankruptcyCount).to.equal(1)
      expect(restored.seenTutorial).to.equal(true)
      expect(restored.shipCargo[1]).to.equal(10)
      expect(restored.warehouseCargo[1]).to.equal(20)
    end)

    it("computes holdSpace from restored shipCapacity and shipCargo (not from constants)", function()
      -- shipCapacity=60, shipCargo={10,5,0,0}=15, guns=2 → 60-15-20=25
      local restored = PE.deserialize(PE.serialize(makeState()), PriceEngine)
      expect(restored.holdSpace).to.equal(60 - 10 - 5 - 0 - 0 - 2*10)
    end)

    it("computes warehouseUsed from warehouseCargo", function()
      local restored = PE.deserialize(PE.serialize(makeState()), PriceEngine)
      expect(restored.warehouseUsed).to.equal(20)
    end)

    it("sets destination to currentPort", function()
      local restored = PE.deserialize(PE.serialize(makeState()), PriceEngine)
      expect(restored.destination).to.equal(3)
    end)

    it("computes currentPrices (non-nil table)", function()
      local restored = PE.deserialize(PE.serialize(makeState()), PriceEngine)
      expect(restored.currentPrices).never.to.equal(nil)
      expect(type(restored.currentPrices)).to.equal("table")
    end)

    it("resets ephemeral fields to correct defaults", function()
      local s = makeState()
      s.combat    = { someField = true }
      s.shipOffer = { repairRate = 100 }
      local restored = PE.deserialize(PE.serialize(s), PriceEngine)
      expect(restored.combat).to.equal(nil)
      expect(restored.shipOffer).to.equal(nil)
      expect(restored.inWuSession).to.equal(false)
      expect(restored.liYuenOfferCost).to.equal(nil)
      expect(restored.pendingTutorial).to.equal(nil)
    end)

    it("defaults seenTutorial to false when absent from saved data", function()
      local data = PE.serialize(makeState())
      data.seenTutorial = nil  -- simulate save from older build
      local restored = PE.deserialize(data, PriceEngine)
      expect(restored.seenTutorial).to.equal(false)
    end)
  end)

  describe("dataStoreRetry", function()
    it("returns result on first-call success", function()
      local result = PE.dataStoreRetry(function() return "ok" end, 3)
      expect(result).to.equal("ok")
    end)

    it("retries on failure and returns result on later success", function()
      -- NOTE: this test waits ~1s (retry backoff). That is expected and correct.
      local callCount = 0
      local result = PE.dataStoreRetry(function()
        callCount = callCount + 1
        if callCount < 2 then error("fail") end
        return "success"
      end, 3)
      expect(result).to.equal("success")
      expect(callCount).to.equal(2)
    end)

    it("returns nil after exhausting all attempts", function()
      -- NOTE: this test waits ~3s (1s+2s backoff). That is expected and correct.
      local callCount = 0
      local result = PE.dataStoreRetry(function()
        callCount = callCount + 1
        error("always fail")
      end, 3)
      expect(result).to.equal(nil)
      expect(callCount).to.equal(3)
    end)
  end)
end
```

---

- [ ] **Step 1.3: Inject spec into Studio and verify it fails**

In Roblox Studio (MCP `run_code`, edit/stop mode):

```lua
-- Create/replace the spec module in the Tests folder
local Tests = game:GetService("ReplicatedStorage"):FindFirstChild("Tests")
  or Instance.new("Folder", game:GetService("ReplicatedStorage"))
Tests.Name = "Tests"
Tests.Parent = game:GetService("ReplicatedStorage")

local existing = Tests:FindFirstChild("PersistenceEngine.spec")
if existing then existing:Destroy() end
local m = Instance.new("ModuleScript")
m.Name = "PersistenceEngine.spec"
m.Source = [[ PASTE SPEC SOURCE HERE ]]
m.Parent = Tests
print("PersistenceEngine.spec injected")
```

Then run the test suite. Expected: PersistenceEngine tests fail (module not found).

---

- [ ] **Step 1.4: Write PersistenceEngine.lua**

Create `src/ReplicatedStorage/shared/PersistenceEngine.lua`:

```lua
-- PersistenceEngine.lua
-- Serialise/deserialise game state for DataStore persistence.
-- No Roblox service calls; PriceEngine injected for testability.

local PersistenceEngine = {}

local SCALAR_FIELDS = {
  "startChoice", "cash", "debt", "bankBalance",
  "shipCapacity", "guns", "damage", "pirateBase",
  "currentPort", "month", "year", "turnsElapsed",
  "liYuenProtection", "wuWarningGiven", "bankruptcyCount",
  "enemyBaseDamage", "enemyBaseHP",
  "gameOver", "gameOverReason", "finalScore", "finalRating",
  "seenTutorial",
}

function PersistenceEngine.serialize(state)
  local data = { version = 1 }

  -- Scalar fields
  for _, field in ipairs(SCALAR_FIELDS) do
    data[field] = state[field]
  end

  -- Array fields (shallow copy)
  for _, field in ipairs({ "shipCargo", "warehouseCargo" }) do
    local arr = {}
    for i, v in ipairs(state[field]) do arr[i] = v end
    data[field] = arr
  end

  -- basePrices: deep copy 7×4 nested table
  local bp = {}
  for p = 1, 7 do
    bp[p] = {}
    for g = 1, 4 do bp[p][g] = state.basePrices[p][g] end
  end
  data.basePrices = bp

  return data
end

function PersistenceEngine.deserialize(data, PriceEngine)
  if data == nil then return nil end
  if data.version == nil or data.version ~= 1 then return nil end

  local state = {}

  -- Restore scalar fields
  for _, field in ipairs(SCALAR_FIELDS) do
    state[field] = data[field]
  end
  -- Default missing field from old saves
  if state.seenTutorial == nil then state.seenTutorial = false end

  -- Restore array fields
  for _, field in ipairs({ "shipCargo", "warehouseCargo" }) do
    local arr = {}
    for i, v in ipairs(data[field]) do arr[i] = v end
    state[field] = arr
  end

  -- Restore basePrices
  local bp = {}
  for p = 1, 7 do
    bp[p] = {}
    for g = 1, 4 do bp[p][g] = data.basePrices[p][g] end
  end
  state.basePrices = bp

  -- Derive computed fields from restored canonical data
  -- holdSpace: uses restored shipCapacity (includes upgrades) and restored shipCargo
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2]
    - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  state.warehouseUsed = state.warehouseCargo[1] + state.warehouseCargo[2]
    + state.warehouseCargo[3] + state.warehouseCargo[4]
  -- currentPrices: use the restored (drifted) basePrices, not original constants
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  state.destination   = state.currentPort

  -- Reset ephemeral fields
  state.liYuenOfferCost = nil
  state.inWuSession     = false
  state.pendingTutorial = nil
  state.combat          = nil
  state.shipOffer       = nil

  return state
end

-- Calls fn() up to maxAttempts times with exponential backoff.
-- Waits 1s after attempt 1, 2s after attempt 2 (no wait after last attempt).
-- Returns result on success, nil after all attempts exhausted.
-- Uses task.wait() (not deprecated wait()).
function PersistenceEngine.dataStoreRetry(fn, maxAttempts)
  maxAttempts = maxAttempts or 3
  local waitTime = 1
  for attempt = 1, maxAttempts do
    local ok, result = pcall(fn)
    if ok then return result end
    warn("PersistenceEngine: DataStore attempt " .. attempt
      .. " of " .. maxAttempts .. " failed: " .. tostring(result))
    if attempt < maxAttempts then
      task.wait(waitTime)
      waitTime = waitTime * 2
    end
  end
  return nil
end

return PersistenceEngine
```

---

- [ ] **Step 1.5: Inject PersistenceEngine.lua and GameState.lua into Studio**

**Inject PersistenceEngine** (new ModuleScript in `ReplicatedStorage.shared`):

```lua
local shared = game:GetService("ReplicatedStorage"):FindFirstChild("shared")
local existing = shared:FindFirstChild("PersistenceEngine")
if existing then existing:Destroy() end
local m = Instance.new("ModuleScript")
m.Name = "PersistenceEngine"
m.Source = [[ PASTE PersistenceEngine.lua SOURCE ]]
m.Parent = shared
print("PersistenceEngine injected")
```

**Inject updated GameState** (replace existing ModuleScript source):

```lua
local gs = game:GetService("ReplicatedStorage").shared:FindFirstChild("GameState")
gs.Source = [[ PASTE UPDATED GameState.lua SOURCE ]]
print("GameState updated")
```

---

- [ ] **Step 1.6: Run tests — verify all pass**

Run the TestEZ suite. Expected: all previously passing tests still pass, plus the 11 new PersistenceEngine tests. Note: the two dataStoreRetry retry tests take ~4 seconds total due to backoff waits — this is expected.

Expected total: **~191 tests, 0 failures**.

---

- [ ] **Step 1.7: Commit**

```bash
git add src/ReplicatedStorage/shared/PersistenceEngine.lua \
        tests/PersistenceEngine.spec.lua \
        src/ReplicatedStorage/shared/GameState.lua
git commit -m "feat: Phase 7 Task 1 — PersistenceEngine + spec (serialize/deserialize/retry)"
```

---

## Chunk 2: GameService DataStore wiring + onboarding

### Task 2: Wire DataStore into GameService

**Files:**
- Modify: `src/ServerScriptService/GameService.server.lua`

---

- [ ] **Step 2.1: Add DataStore requires and helper functions**

At the top of `GameService.server.lua`, after line 15 (`local ProgressionEngine = ...`), add:

```lua
local PersistenceEngine = require(ReplicatedStorage.shared.PersistenceEngine)
local DataStoreService  = game:GetService("DataStoreService")
local gameStore         = DataStoreService:GetDataStore("TaipanV1")
```

Add two helpers **before** `pushState`:

```lua
local function savePlayer(player, state)
  local data = PersistenceEngine.serialize(state)
  PersistenceEngine.dataStoreRetry(function()
    gameStore:SetAsync("player_" .. player.UserId, data)
  end)
end

local function loadPlayer(player)
  local data = PersistenceEngine.dataStoreRetry(function()
    return gameStore:GetAsync("player_" .. player.UserId)
  end)
  return PersistenceEngine.deserialize(data, PriceEngine)
end
```

---

- [ ] **Step 2.2: Harden `pushState` against the async sentinel**

The existing `pushState` guard fires for any truthy value. With the sentinel pattern (`playerStates[player] = true` during async load), firing `true` to the client would crash it. Change the guard **before** adding the sentinel anywhere else:

Old:
```lua
local function pushState(player)
  local state = playerStates[player]
  if state then
    Remotes.StateUpdate:FireClient(player, state)
  end
end
```

New:
```lua
local function pushState(player)
  local state = playerStates[player]
  if type(state) == "table" then  -- guard against boolean sentinel during async load
    Remotes.StateUpdate:FireClient(player, state)
  end
end
```

---

- [ ] **Step 2.3: Update all handler nil-guards to type-check against the sentinel**

Handlers use two guard patterns. Both must be updated.

**Pattern A** — simple nil guard (single line):
```lua
if not state then return end
```
Replace with:
```lua
if type(state) ~= "table" then return end
```
Handlers using Pattern A: `BuyGoods`, `SellGoods`, `EndTurn`, `TravelTo`, `TransferToWarehouse`, `TransferFromWarehouse`, `WuRepay`, `WuBorrow`, `LeaveWu`, `BankDeposit`, `BankWithdraw`, `BuyLiYuenProtection`, `ShipPanelDone`.

Note: `RequestStateUpdate` has no nil guard — it calls `pushState(player)` directly, which already contains the type check. Do not modify it.

Note: `RestartGame` also has Pattern A on its first guard line, but it is fully replaced in Step 2.6 — do not edit it here.

Note: `ChooseStart` uses `if playerStates[player] then return end` (truthy check on the map, not on `state`). This is correct as-is and should **not** be changed.

**Pattern B** — compound guard (single line with `or`):
```lua
if not state or not state.combat or state.combat.outcome ~= nil then return end
```
Replace with:
```lua
if type(state) ~= "table" or not state.combat or state.combat.outcome ~= nil then return end
```
Handlers using Pattern B (combat): `CombatFight`, `CombatRun`, `CombatThrow`.

**Pattern C** — compound guard with `state.gameOver`:
```lua
if not state or state.gameOver then return end
```
Replace with:
```lua
if type(state) ~= "table" or state.gameOver then return end
```
Handlers using Pattern C: `ShipRepair`, `AcceptUpgrade`, `DeclineUpgrade`, `AcceptGun`, `DeclineGun`, `Retire`, `QuitGame`.

Leave any second guard line in the same handler (e.g. `if not state.shipOffer then return end`) unchanged — these only run after the type check passes.

---

- [ ] **Step 2.4: Modify `ChooseStart` to load save data**

Replace the current `ChooseStart` handler body with:

```lua
Remotes.ChooseStart.OnServerEvent:Connect(function(player, startChoice)
  if startChoice ~= "cash" and startChoice ~= "guns" then startChoice = "cash" end
  if playerStates[player] then return end           -- already initialised (or sentinel)
  playerStates[player] = true                       -- sentinel: claim slot before async
  -- RequestStateUpdate calling pushState during this window silently no-ops (type guard).

  local loaded = loadPlayer(player)                 -- yields on DataStore call
  if loaded then
    -- Works for both resumed games (gameOver=false) and game-over saves (gameOver=true).
    -- Client renders whichever screen is appropriate from the pushed state.
    playerStates[player] = loaded
    pushState(player)
    return
  end

  -- No save found: start a fresh game
  local state = GameState.newGame(startChoice)
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  state.holdSpace = state.shipCapacity
  -- state.seenTutorial is already false (set by GameState.newGame)
  state.pendingTutorial = true  -- fires tutorial on first HK arrival; not in newGame
  playerStates[player] = state
  pushState(player)
end)
```

---

- [ ] **Step 2.5: Add onboarding check and departure save to `TravelTo`**

Inside the `TravelTo` handler, directly before the final `pushState(player)` call at the end of the handler, add:

```lua
  -- Onboarding: fire tutorial messages on first HK arrival of a new game
  if destination == Constants.HONG_KONG and state.pendingTutorial then
    state.pendingTutorial = nil
    Remotes.Notify:FireClient(player,
      "Welcome, Taipan! Visit Elder Brother Wu to borrow cash or repay your debt.")
    Remotes.Notify:FireClient(player,
      "Use the Warehouse to store goods safely between voyages — holds up to 10,000 units.")
    Remotes.Notify:FireClient(player,
      "Li Yuen commands the seas. Pay for his protection in Hong Kong to avoid his fleet.")
    state.seenTutorial = true
    savePlayer(player, state)  -- persist immediately so tutorial never repeats on reconnect
  end

  pushState(player)
  savePlayer(player, state)  -- save on every departure
end)  -- existing handler close — shown for context; do NOT insert this line
```

The existing `TravelTo` handler ends with `pushState(player)` then `end)`. Insert `savePlayer(player, state)` between those two existing lines. On a new player's first travel to HK, both `savePlayer` calls fire (tutorial save + departure save) — harmless, the second write wins.

---

- [ ] **Step 2.6: Modify `RestartGame` to carry `seenTutorial` forward**

Replace the `RestartGame` handler with:

```lua
Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.gameOver then return end
  local wasTutorialSeen = state.seenTutorial  -- preserve so tutorial doesn't replay
  local newState = GameState.newGame("cash")
  newState.currentPrices = PriceEngine.calculatePrices(newState.basePrices, newState.currentPort)
  newState.holdSpace = newState.shipCapacity
  newState.seenTutorial = wasTutorialSeen
  if not wasTutorialSeen then
    newState.pendingTutorial = true  -- tutorial still pending; fires on first HK arrival
  end
  playerStates[player] = newState
  pushState(player)
end)
```

---

- [ ] **Step 2.7: Add save to `Players.PlayerRemoving` and add `BindToClose`**

Replace the existing `PlayerRemoving` handler:

```lua
Players.PlayerRemoving:Connect(function(player)
  local state = playerStates[player]
  if type(state) == "table" then
    savePlayer(player, state)  -- save before removing from map
  end
  playerStates[player] = nil
end)
```

Add `BindToClose` immediately after:

```lua
-- Failsafe save on server shutdown (covers force-close / studio stop).
-- DataStore calls yield the coroutine; saves are sequential.
-- Max 3s backoff per player; well within Roblox's ~30s BindToClose budget.
game:BindToClose(function()
  for player, state in pairs(playerStates) do
    if type(state) == "table" then
      savePlayer(player, state)
    end
  end
end)
```

---

- [ ] **Step 2.8: Inject updated GameService into Studio**

GameService is a `Script` instance (not `ModuleScript`). Its `.Source` cannot be assigned directly — destroy and recreate:

```lua
local SSS = game:GetService("ServerScriptService")
local old = SSS:FindFirstChild("GameService")
if old then old:Destroy() end
local s = Instance.new("Script")
s.Name = "GameService"
s.Source = [[ PASTE FULL UPDATED GameService SOURCE ]]
s.Parent = SSS
print("GameService injected")
```

---

- [ ] **Step 2.9: Run tests — verify all existing tests still pass**

Run the TestEZ suite in Studio edit mode. DataStore calls do not work in Studio edit mode (they throw errors caught by `pcall`), but the pure-logic tests are unaffected.

Expected: same ~191 tests, 0 failures.

---

- [ ] **Step 2.10: Manual smoke test in Play mode**

Start Play mode in Studio. Open the console. Travel from HK to another port. Expected console output: save attempt fires (may show DataStore error in Studio — this is normal; DataStore is not enabled in Studio by default).

Verify:
- Game starts and loads normally
- Travelling fires `savePlayer` (no Lua errors)
- Tutorial messages fire on first HK arrival (check MessagePanel)
- Restarting from game-over doesn't repeat tutorial

---

- [ ] **Step 2.11: Commit**

```bash
git add src/ServerScriptService/GameService.server.lua
git commit -m "feat: Phase 7 Task 2 — DataStore save/load, sentinel pattern, onboarding tutorial"
```

---

## Chunk 3: UI Polish Pass

### Task 3: Mobile 44px + Colour Audit (all panels)

**Files (all modify):**
- `src/StarterGui/TaipanGui/Panels/BuySellPanel.lua`
- `src/StarterGui/TaipanGui/Panels/WarehousePanel.lua`
- `src/StarterGui/TaipanGui/Panels/WuPanel.lua`
- `src/StarterGui/TaipanGui/Panels/BankPanel.lua`
- `src/StarterGui/TaipanGui/Panels/ShipPanel.lua`
- `src/StarterGui/TaipanGui/Panels/CombatPanel.lua`
- `src/StarterGui/TaipanGui/Panels/GameOverPanel.lua`
- `src/StarterGui/TaipanGui/Panels/PortPanel.lua`

**Colour palette (reference):**

| Role | `Color3.fromRGB(...)` | Use |
|---|---|---|
| Amber | `200, 180, 80` | Titles, labels, data values, date |
| Green | `140, 200, 80` | Action buttons, positive outcomes |
| Red | `220, 80, 80` | Quit, game-over, danger |
| Orange | `220, 120, 60` | Repair/damage warning |
| Blue | `120, 120, 220` | Gun purchase |
| Grey | `80, 80, 80` | Disabled, current port |

---

- [ ] **Step 3.1: BuySellPanel — raise buttons and input to 44px**

In `BuySellPanel.lua`, raise all interactive element heights. The good selector buttons and amount box are 28px; Buy/Sell/EndTurn are 36px. Raise all to 44px and adjust positions to maintain 6px spacing:

```
y=5:  good buttons 44px  (was 28px) → bottom at y=49
y=55: amount box   44px  (was 28px at y=40) → bottom at y=99
y=105: buy/sell/end turn 44px (was 36px at y=75) → bottom at y=149
frame height: 165px (was 200px)
```

Key size changes:
- `GoodBtn` size: `UDim2.new(0.22, -4, 0, 44)`
- `AmountBox` size: `UDim2.new(0.5, -5, 0, 44)`, position: `UDim2.new(0, 5, 0, 55)`
- `BuyBtn`, `SellBtn`, `EndTurnBtn` size height: `0, 44`, position y: `0, 105`
- Frame: `UDim2.new(1, 0, 0, 165)`

---

- [ ] **Step 3.2: WarehousePanel — raise buttons and input to 44px**

Read `WarehousePanel.lua` first, then raise any buttons/inputs at 28px to 44px. Adjust frame height and downstream position to maintain layout. Use the same 6px spacing rhythm.

---

- [ ] **Step 3.3: WuPanel — raise buttons and input to 44px**

Read `WuPanel.lua` first. Raise repay/borrow/leave/protection buttons and amount input to 44px. Adjust frame height. The WuPanel is a modal overlay (like ShipPanel) so no downstream cascade needed — it fills the screen.

---

- [ ] **Step 3.4: BankPanel — raise buttons and input to 44px**

Read `BankPanel.lua` first. Raise deposit/withdraw buttons and amount input to 44px.

---

- [ ] **Step 3.5: ShipPanel — raise buttons and input to 44px**

ShipPanel uses sub-frames for each section. Read `ShipPanel.lua` first. Raise all `TextButton` and `TextBox` elements (repair/all/done/accept/decline) from 28px to 44px. Adjust each sub-frame height accordingly. The sub-frames stack; update their vertical positions.

---

- [ ] **Step 3.6: CombatPanel — raise buttons and input to 44px**

Read `CombatPanel.lua` first. Raise fight/run/throw buttons and quantity input to 44px.

---

- [ ] **Step 3.7: GameOverPanel and PortPanel — raise remaining buttons**

- `GameOverPanel.lua`: raise Restart button to 44px.
- `PortPanel.lua`: raise Retire and Quit buttons from 24px to 44px. Adjust frame height (currently 120px) and any internal positions.

---

- [ ] **Step 3.8: Colour audit — fix off-palette colours across all 8 panels**

For each panel, scan `TextColor3`, `BackgroundColor3`, `BorderColor3` values:

- Any title/label colour not matching Amber `(200, 180, 80)` → update
- Any action button text not matching Green `(140, 200, 80)` → update
- Any danger/quit button text not matching Red `(220, 80, 80)` → update
- Repair-related text should use Orange `(220, 120, 60)`
- Gun purchase should use Blue `(120, 120, 220)`
- Disabled/current-port should use Grey `(80, 80, 80)`

Common off-palette values to watch for:
- `(255, 200, 50)` → replace with Amber `(200, 180, 80)`
- `(100, 255, 100)` → replace with Green `(140, 200, 80)`
- `(255, 100, 100)` → replace with Red `(220, 80, 80)`
- `(160, 160, 160)` → replace with Grey `(80, 80, 80)` if used for disabled

---

- [ ] **Step 3.9: Inject all 8 panels into Studio**

For each panel, inject as a ModuleScript into `StarterGui.TaipanGui.Panels` (the `Panels` folder is a direct child of the `TaipanGui` LocalScript — there is no intermediate `GameController` folder):

```lua
local Panels = game:GetService("StarterGui").TaipanGui.Panels
local existing = Panels:FindFirstChild("BuySellPanel")  -- repeat for each
if existing then existing:Destroy() end
local m = Instance.new("ModuleScript")
m.Name = "BuySellPanel"
m.Source = [[ PASTE PANEL SOURCE ]]
m.Parent = Panels
```

---

- [ ] **Step 3.10: Visual verification in Play mode**

Start Play mode. Verify:
- All buttons are clearly tappable (visually large enough)
- Amber labels throughout (port name, date, prices)
- Green action buttons
- No jarring colour inconsistencies
- Panels scroll correctly on a narrow viewport (resize Studio window to phone proportions: ~390px wide)

---

- [ ] **Step 3.11: Commit**

```bash
git add src/StarterGui/TaipanGui/Panels/
git commit -m "feat: Phase 7 Task 3 — UI polish: 44px touch targets + colour audit"
```

---

## Milestone Test Checklist

After all three tasks are committed:

- [ ] Play a full game, travel 3+ ports, force-quit Studio
- [ ] Reopen — confirm game resumes at correct port with correct cash/cargo/debt
- [ ] Play to game-over (sunk). Reopen — confirm game-over screen shown
- [ ] Click Restart — confirm tutorial does NOT repeat (`seenTutorial` carried forward)
- [ ] Resize Studio window to ~390px wide — confirm all buttons reachable without overlap
- [ ] New player flow: first travel to HK fires 3 tutorial Notify messages
