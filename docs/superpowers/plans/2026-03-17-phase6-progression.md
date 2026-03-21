# Phase 6: Ship Progression + Score + Retirement — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ship repair, upgrade/gun offers at Hong Kong, score/rating system, retirement win condition, and a complete game-over screen for all endings (sunk, quit, retired).

**Architecture:** New `ProgressionEngine` pure-logic module handles all repair/upgrade/gun/score math. Server sets `state.shipOffer` on HK arrival; `ShipPanel` client UI handles the offers. `gameOverReason` + `finalScore` + `finalRating` fields flow to an extended `GameOverPanel`. QUIT and RETIRE buttons are added to `PortPanel`.

**Tech Stack:** Luau, Roblox RemoteEvents (server-auth), TestEZ, Roblox Studio MCP injection.

---

## Chunk 1: ProgressionEngine — pure logic + tests

### Task 1: ProgressionEngine.lua + ProgressionEngine.spec.lua

**Files:**
- Create: `src/ReplicatedStorage/shared/ProgressionEngine.lua`
- Create: `tests/ProgressionEngine.spec.lua`

---

- [ ] **Step 1.1: Write the failing tests first**

Create `tests/ProgressionEngine.spec.lua`:

```lua
-- ProgressionEngine.spec.lua
return function()
  local PE = require(game:GetService("ReplicatedStorage").shared.ProgressionEngine)

  local function makeState(overrides)
    local s = {
      cash         = 10000,
      bankBalance  = 5000,
      debt         = 2000,
      shipCapacity = 60,
      holdSpace    = 40,
      damage       = 0,
      guns         = 0,
      turnsElapsed = 1,
    }
    if overrides then
      for k, v in pairs(overrides) do s[k] = v end
    end
    return s
  end

  describe("repairRate", function()
    it("returns a positive integer", function()
      local s = makeState({ damage = 5 })
      local br = PE.repairRate(s)
      expect(typeof(br)).to.equal("number")
      expect(br >= 1).to.equal(true)
      expect(math.floor(br)).to.equal(br)
    end)
    it("increases with turnsElapsed", function()
      -- Average BR at TI=1 < average BR at TI=13, run many times
      local sum1, sum13 = 0, 0
      for _ = 1, 200 do
        sum1  = sum1  + PE.repairRate(makeState({ turnsElapsed = 1,  shipCapacity = 60 }))
        sum13 = sum13 + PE.repairRate(makeState({ turnsElapsed = 13, shipCapacity = 60 }))
      end
      expect(sum13 > sum1).to.equal(true)
    end)
    it("minimum 1 even with tiny SC", function()
      -- math.max(1, br) clamp: SC=1 gives near-zero BR before clamp
      for _ = 1, 20 do
        local br = PE.repairRate(makeState({ shipCapacity = 1, turnsElapsed = 1 }))
        expect(br >= 1).to.equal(true)
      end
    end)
  end)

  describe("repairAmount", function()
    it("returns INT(W/BR + 0.5)", function()
      expect(PE.repairAmount(100, 150)).to.equal(2)   -- 1.5+0.5=2.0 -> 2
      expect(PE.repairAmount(100, 249)).to.equal(2)   -- 2.49+0.5=2.99 -> 2 (wait, 249/100=2.49, +0.5=2.99 -> floor=2)
      expect(PE.repairAmount(100, 250)).to.equal(3)   -- 2.5+0.5=3.0 -> 3
      expect(PE.repairAmount(100, 0)).to.equal(0)
    end)
    it("returns 0 for BR=0", function()
      expect(PE.repairAmount(0, 100)).to.equal(0)
    end)
  end)

  describe("repairAllCost", function()
    -- Note: uses math.ceil(damage) rather than raw damage (BASIC formula BR*DM+1).
    -- Reason: our damage is fractional (combat accumulates I/2 terms). With raw DM,
    -- BR*2.1+1=211 only repairs INT(2.61)=2 points, leaving 0.1 damage — not a full repair.
    -- math.ceil ensures "All" always covers full fractional damage.
    it("returns BR * ceil(damage) + 1", function()
      expect(PE.repairAllCost(100, 3)).to.equal(301)
      expect(PE.repairAllCost(100, 2.1)).to.equal(301)  -- ceil(2.1)=3, so 300+1=301
      expect(PE.repairAllCost(100, 0)).to.equal(1)
    end)
    it("fully repairs fractional damage when W = repairAllCost", function()
      -- With BR=100, damage=2.1: allCost=301, repairAmount(100,301)=3, capped at ceil(2.1)=3
      -- state.damage = max(0, 2.1-3) = 0 — fully repaired
      local s = makeState({ cash = 500, damage = 2.1 })
      local allCost = PE.repairAllCost(100, s.damage)
      PE.applyRepair(s, 100, allCost)
      expect(s.damage).to.equal(0)
    end)
  end)

  describe("applyRepair", function()
    it("deducts cash and reduces damage", function()
      local s = makeState({ cash = 1000, damage = 5 })
      local repaired = PE.applyRepair(s, 100, 300)  -- 300/100+0.5=3.5->3, but capped at 5
      expect(repaired).to.equal(3)
      expect(s.cash).to.equal(700)
      expect(s.damage).to.equal(2)
    end)
    it("caps repaired damage at actual damage", function()
      local s = makeState({ cash = 5000, damage = 2 })
      local repaired = PE.applyRepair(s, 100, 5000)  -- would repair 50 but only 2 damage
      expect(repaired).to.equal(2)
      expect(s.damage).to.equal(0)
    end)
    it("returns 0 if no damage", function()
      local s = makeState({ cash = 1000, damage = 0 })
      expect(PE.applyRepair(s, 100, 500)).to.equal(0)
    end)
    it("returns 0 if insufficient cash", function()
      local s = makeState({ cash = 50, damage = 5 })
      expect(PE.applyRepair(s, 100, 500)).to.equal(0)
    end)
    it("returns 0 if W <= 0", function()
      local s = makeState({ cash = 1000, damage = 5 })
      expect(PE.applyRepair(s, 100, 0)).to.equal(0)
    end)
  end)

  describe("checkUpgradeOffer", function()
    it("returns nil or a positive number", function()
      local gotOffer, gotNil = false, false
      for _ = 1, 500 do
        local cost = PE.checkUpgradeOffer(makeState())
        if cost == nil then gotNil = true
        else
          expect(typeof(cost)).to.equal("number")
          expect(cost > 0).to.equal(true)
          gotOffer = true
        end
      end
      expect(gotNil).to.equal(true)
      expect(gotOffer).to.equal(true)
    end)
  end)

  describe("applyUpgrade", function()
    it("adds 50 capacity, repairs all damage, deducts cash", function()
      local s = makeState({ cash = 50000, shipCapacity = 60, holdSpace = 30, damage = 10 })
      local ok = PE.applyUpgrade(s, 5000)
      expect(ok).to.equal(true)
      expect(s.shipCapacity).to.equal(110)
      expect(s.holdSpace).to.equal(80)
      expect(s.damage).to.equal(0)
      expect(s.cash).to.equal(45000)
    end)
    it("returns false if cash < cost", function()
      local s = makeState({ cash = 100 })
      expect(PE.applyUpgrade(s, 5000)).to.equal(false)
    end)
  end)

  describe("checkGunOffer", function()
    it("returns nil or a positive number when holdSpace >= 10", function()
      local gotOffer, gotNil = false, false
      for _ = 1, 500 do
        local cost = PE.checkGunOffer(makeState({ holdSpace = 20 }))
        if cost == nil then gotNil = true
        else
          expect(typeof(cost)).to.equal("number")
          expect(cost > 0).to.equal(true)
          gotOffer = true
        end
      end
      expect(gotNil).to.equal(true)
      expect(gotOffer).to.equal(true)
    end)
    it("always returns nil when holdSpace < 10", function()
      for _ = 1, 100 do
        expect(PE.checkGunOffer(makeState({ holdSpace = 9 }))).to.equal(nil)
      end
    end)
  end)

  describe("applyGun", function()
    it("adds gun, reduces holdSpace by 10, deducts cash", function()
      local s = makeState({ cash = 5000, guns = 2, holdSpace = 20 })
      local ok = PE.applyGun(s, 800)
      expect(ok).to.equal(true)
      expect(s.guns).to.equal(3)
      expect(s.holdSpace).to.equal(10)
      expect(s.cash).to.equal(4200)
    end)
    it("returns false if cash < cost", function()
      local s = makeState({ cash = 100, holdSpace = 20 })
      expect(PE.applyGun(s, 800)).to.equal(false)
    end)
    it("returns false if holdSpace < 10", function()
      local s = makeState({ cash = 5000, holdSpace = 9 })
      expect(PE.applyGun(s, 800)).to.equal(false)
    end)
  end)

  describe("netWorth", function()
    it("returns cash + bank - debt", function()
      local s = makeState({ cash = 10000, bankBalance = 5000, debt = 2000 })
      expect(PE.netWorth(s)).to.equal(13000)
    end)
    it("can be negative", function()
      local s = makeState({ cash = 0, bankBalance = 0, debt = 5000 })
      expect(PE.netWorth(s)).to.equal(-5000)
    end)
  end)

  describe("score", function()
    it("returns INT((cash+bank-debt)/100/TI^1.1)", function()
      -- With cash=1000000, bank=0, debt=0, TI=1: score = INT(1000000/100/1) = 10000
      local s = makeState({ cash = 1000000, bankBalance = 0, debt = 0, turnsElapsed = 1 })
      expect(PE.score(s)).to.equal(10000)
    end)
    it("returns 0 for net worth <= 0", function()
      local s = makeState({ cash = 0, bankBalance = 0, debt = 10000, turnsElapsed = 5 })
      expect(PE.score(s) <= 0).to.equal(true)
    end)
  end)

  describe("rating", function()
    it("Ma Tsu for score >= 50000", function()
      expect(PE.rating(50000)).to.equal("Ma Tsu")
      expect(PE.rating(99999)).to.equal("Ma Tsu")
    end)
    it("Master for 8000-49999", function()
      expect(PE.rating(8000)).to.equal("Master")
      expect(PE.rating(49999)).to.equal("Master")
    end)
    it("Taipan for 1000-7999", function()
      expect(PE.rating(1000)).to.equal("Taipan")
      expect(PE.rating(7999)).to.equal("Taipan")
    end)
    it("Compradore for 500-999", function()
      expect(PE.rating(500)).to.equal("Compradore")
      expect(PE.rating(999)).to.equal("Compradore")
    end)
    it("Galley Hand for < 500", function()
      expect(PE.rating(499)).to.equal("Galley Hand")
      expect(PE.rating(0)).to.equal("Galley Hand")
      expect(PE.rating(-1)).to.equal("Galley Hand")
    end)
  end)

  describe("canRetire", function()
    it("true when netWorth >= 1000000", function()
      local s = makeState({ cash = 1000000, bankBalance = 0, debt = 0 })
      expect(PE.canRetire(s)).to.equal(true)
    end)
    it("false when netWorth < 1000000", function()
      local s = makeState({ cash = 999999, bankBalance = 0, debt = 0 })
      expect(PE.canRetire(s)).to.equal(false)
    end)
  end)
end
```

- [ ] **Step 1.2: Inject spec into Studio Tests folder and verify it fails**

```lua
-- Run in Studio (edit mode) via run_code:
local Tests = game:GetService("ServerScriptService"):FindFirstChild("Tests")
local existing = Tests:FindFirstChild("ProgressionEngine.spec")
if existing then existing:Destroy() end
local m = Instance.new("ModuleScript")
m.Name = "ProgressionEngine.spec"
m.Source = [[ -- paste spec content ]]
m.Parent = Tests
print("ProgressionEngine.spec injected")
```

Expected: TestEZ fails because `ProgressionEngine` doesn't exist yet.

- [ ] **Step 1.3: Implement ProgressionEngine.lua**

Create `src/ReplicatedStorage/shared/ProgressionEngine.lua`:

```lua
-- ProgressionEngine.lua
-- Pure logic: ship repair, upgrade/gun offers, score, rating, retirement.
-- No Roblox service calls.

local ProgressionEngine = {}

local function fnR(x)
  local n = math.floor(x)
  if n <= 0 then return 0 end
  return math.random(0, n - 1)
end

-- Cost per damage point for repair.
-- BR = INT((FN_R(60*(TI+3)/4) + 25*(TI+3)/4) * SC/50)
-- Minimum 1 to avoid division by zero.
function ProgressionEngine.repairRate(state)
  local ti = state.turnsElapsed
  local sc = state.shipCapacity
  local br = math.floor((fnR(60*(ti+3)/4) + 25*(ti+3)/4) * sc/50)
  return math.max(1, br)
end

-- Damage repaired when spending W cash at given repair rate.
-- = INT(W/BR + 0.5)  (round to nearest integer)
function ProgressionEngine.repairAmount(br, w)
  if br <= 0 then return 0 end
  return math.floor(w / br + 0.5)
end

-- Cash needed to repair all damage ("All" button).
-- BASIC formula: BR*DM+1 (DM was always integer in BASIC).
-- Luau adaptation: uses math.ceil(damage) because our damage is fractional
-- (combat accumulates I/2 terms). Raw DM=2.1 → BR*2.1+1=211 → repairAmount=2, leaving 0.1
-- damage; ceil ensures the "All" cost guarantees a complete repair.
function ProgressionEngine.repairAllCost(br, damage)
  return br * math.ceil(damage) + 1
end

-- Apply repair: spend W cash, reduce damage.
-- Uses pre-computed repairRate (stored in state.shipOffer.repairRate).
-- Returns number of damage points repaired, or 0 if invalid.
-- NOTE: W is capped at state.cash before calling (server must validate).
function ProgressionEngine.applyRepair(state, repairRate, w)
  if w <= 0 or w > state.cash or state.damage <= 0 then return 0 end
  local repaired = math.min(
    ProgressionEngine.repairAmount(repairRate, w),
    math.ceil(state.damage)
  )
  if repaired <= 0 then return 0 end
  state.cash   = state.cash - w
  state.damage = math.max(0, state.damage - repaired)
  return repaired
end

-- Upgrade offer: 1-in-4 chance (fnR(4)==0).
-- Cost = INT(1000 + FN_R(1000*(TI+5)/6)) * (INT(SC/50)*(DM>0)+1)
-- Returns cost (number) if offer fires, nil otherwise.
function ProgressionEngine.checkUpgradeOffer(state)
  if fnR(4) ~= 0 then return nil end
  local ti   = state.turnsElapsed
  local sc   = state.shipCapacity
  local dm   = state.damage
  local base = math.floor(1000 + fnR(1000*(ti+5)/6))
  local mult = math.floor(sc/50) * (dm > 0 and 1 or 0) + 1
  return base * mult
end

-- Apply upgrade: adds 50 hold capacity, repairs all damage, deducts cost.
-- Returns true on success, false if insufficient cash.
function ProgressionEngine.applyUpgrade(state, cost)
  if state.cash < cost then return false end
  state.cash         = state.cash - cost
  state.shipCapacity = state.shipCapacity + 50
  state.holdSpace    = state.holdSpace + 50
  state.damage       = 0
  return true
end

-- Gun offer: 1-in-3 chance (fnR(3)==0), requires holdSpace >= 10.
-- Cost = INT(FN_R(1000*(TI+5)/6) + 500)
-- Returns cost (number) if offer fires, nil otherwise.
function ProgressionEngine.checkGunOffer(state)
  if state.holdSpace < 10 then return nil end
  if fnR(3) ~= 0 then return nil end
  local ti = state.turnsElapsed
  return math.floor(fnR(1000*(ti+5)/6) + 500)
end

-- Apply gun purchase: +1 gun, -10 holdSpace, deducts cost.
-- Returns true on success, false if insufficient cash or hold.
function ProgressionEngine.applyGun(state, cost)
  if state.cash < cost then return false end
  if state.holdSpace < 10 then return false end
  state.cash      = state.cash - cost
  state.guns      = state.guns + 1
  state.holdSpace = state.holdSpace - 10
  return true
end

-- Net worth: CA + BA - DW
function ProgressionEngine.netWorth(state)
  return state.cash + state.bankBalance - state.debt
end

-- Score: INT((CA+BA-DW) / 100 / TI^1.1)
function ProgressionEngine.score(state)
  local nw = ProgressionEngine.netWorth(state)
  local ti = state.turnsElapsed
  return math.floor(nw / 100 / (ti ^ 1.1))
end

-- Rating based on score.
function ProgressionEngine.rating(sc)
  if sc >= 50000 then return "Ma Tsu"
  elseif sc >= 8000 then return "Master"
  elseif sc >= 1000 then return "Taipan"
  elseif sc >= 500  then return "Compradore"
  else                   return "Galley Hand"
  end
end

-- Whether player may retire (net worth >= 1,000,000).
function ProgressionEngine.canRetire(state)
  return ProgressionEngine.netWorth(state) >= 1000000
end

return ProgressionEngine
```

- [ ] **Step 1.4: Inject ProgressionEngine into Studio**

Inject the module into `ReplicatedStorage.shared.ProgressionEngine` (edit mode).

- [ ] **Step 1.5: Run tests — verify all ProgressionEngine tests pass**

```lua
-- Run in Studio via run_code (edit mode):
local TestEZ = require(game:GetService("ReplicatedStorage").TestEZ)
local results = TestEZ.TestBootstrap:run({
  game:GetService("ServerScriptService").Tests
})
print(string.format("Tests: %d passed, %d failed, %d skipped",
  results.successCount, results.failureCount, results.skippedCount))
if results.failureCount > 0 then
  for _, f in ipairs(results.failures) do
    print("FAIL: " .. table.concat(f.trace, " > "))
  end
end
```

Expected output: `Tests: N passed, 0 failed, 0 skipped` (all pass including prior 149 + new ProgressionEngine tests).

- [ ] **Step 1.6: Commit**

```bash
git add src/ReplicatedStorage/shared/ProgressionEngine.lua tests/ProgressionEngine.spec.lua
git commit -m "feat: Phase 6 Task 1 — ProgressionEngine logic + 30 tests"
```

---

## Chunk 2: Server — GameState + Remotes + GameService

### Task 2: GameState new fields + Remotes + GameService HK offers + all new handlers

**Files:**
- Modify: `src/ReplicatedStorage/shared/GameState.lua`
- Modify: `src/ReplicatedStorage/Remotes.lua`
- Modify: `src/ServerScriptService/GameService.server.lua`

---

- [ ] **Step 2.1: Add new fields to GameState.lua**

In `GameState.newGame`, add after `combat = nil`:

```lua
-- Phase 6: progression
gameOverReason = nil,   -- "sunk" | "quit" | "retired" (nil = game in progress)
finalScore     = nil,   -- set at game over
finalRating    = nil,   -- set at game over
shipOffer      = nil,   -- set on HK arrival: { repairRate=BR, upgradeOffer={cost=X}|nil, gunOffer={cost=Y}|nil }
```

Also add `ProgressionEngine = nil` as a require reminder note (no code change needed there — GameState doesn't import it).

- [ ] **Step 2.2: Add Phase 6 remotes to Remotes.lua**

After the Phase 5 combat remotes block, add:

```lua
-- Phase 6: Ship progression + retirement
Remotes.ShipRepair     = getOrCreate("RemoteEvent", "ShipRepair")     -- amount (cash to spend)
Remotes.AcceptUpgrade  = getOrCreate("RemoteEvent", "AcceptUpgrade")  -- no args
Remotes.DeclineUpgrade = getOrCreate("RemoteEvent", "DeclineUpgrade") -- no args
Remotes.AcceptGun      = getOrCreate("RemoteEvent", "AcceptGun")      -- no args
Remotes.DeclineGun     = getOrCreate("RemoteEvent", "DeclineGun")     -- no args
Remotes.ShipPanelDone  = getOrCreate("RemoteEvent", "ShipPanelDone")  -- dismiss ship panel
Remotes.Retire         = getOrCreate("RemoteEvent", "Retire")         -- retire (HK, netWorth>=1M)
Remotes.QuitGame       = getOrCreate("RemoteEvent", "QuitGame")       -- quit game (any time)
```

- [ ] **Step 2.3: Add ProgressionEngine require to GameService.server.lua**

After the existing `local CombatEngine` require line, add:

```lua
local ProgressionEngine = require(ReplicatedStorage.shared.ProgressionEngine)
```

- [ ] **Step 2.4: Add `setGameOver` helper to GameService**

Add BEFORE `postCombatStorm` (so `postCombatStorm` can call it — Lua local variables must be defined before use):

```lua
-- Sets game-over state and computes final score/rating.
local function setGameOver(state, reason)
  state.gameOver       = true
  state.gameOverReason = reason
  local sc             = ProgressionEngine.score(state)
  state.finalScore     = sc
  state.finalRating    = ProgressionEngine.rating(sc)
  state.combat         = nil
  state.shipOffer      = nil
end
```

- [ ] **Step 2.5: Fix combat sunk path to set gameOver**

In `applyEnemyFire`, the `fireResult.sunk` branch currently only sets `state.combat = nil`. Replace:

```lua
  if fireResult.sunk then
    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    state.combat = nil
    return true
  end
```

With:

```lua
  if fireResult.sunk then
    Remotes.Notify:FireClient(player, "The buggers got us, Taipan!!! It's all over!!!")
    setGameOver(state, "sunk")
    return true
  end
```

- [ ] **Step 2.6: Fix storm sunk paths to set gameOverReason**

There are TWO places where `EventEngine.stormSinks` is called:

**A) In the `TravelTo` handler** — `stormSinks` already sets `state.gameOver = true`. After that call, add reason + score inline (do NOT call `setGameOver` — it would double-set `gameOver`):

```lua
if EventEngine.stormSinks(state) then
  Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
  -- stormSinks already sets state.gameOver = true; add reason + score
  local sc = ProgressionEngine.score(state)
  state.gameOverReason = "sunk"
  state.finalScore     = sc
  state.finalRating    = ProgressionEngine.rating(sc)
```

**B) In `postCombatStorm`** — at this call site, `state.combat` is already `nil` (cleared before `postCombatStorm` is called). Replace the bare early return with a `setGameOver` call:

Current:
```lua
    if EventEngine.stormSinks(state) then
      Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
      return  -- sunk — no blown-off-course
    end
```

Replace with:
```lua
    if EventEngine.stormSinks(state) then
      Remotes.Notify:FireClient(player, "We're going down, Taipan!!")
      -- stormSinks sets gameOver=true; setGameOver adds reason/score (combat already nil)
      setGameOver(state, "sunk")
      return
    end
```

NOTE: `setGameOver` is safe here because `state.combat = nil` is a no-op (already cleared), and `setGameOver` is defined before `postCombatStorm` in the file (Step 2.4).

- [ ] **Step 2.7: Add HK arrival ship offers to TravelTo handler**

In `TravelTo`, after the combat encounter block and before `pushState(player)`, add:

```lua
  -- Phase 6: set ship offers on HK arrival
  if destination == Constants.HONG_KONG then
    local upgradeOffer = ProgressionEngine.checkUpgradeOffer(state)
    local gunOffer     = ProgressionEngine.checkGunOffer(state)
    local repairRate   = (state.damage > 0)
                         and ProgressionEngine.repairRate(state)
                         or  nil
    if repairRate or upgradeOffer or gunOffer then
      state.shipOffer = {
        repairRate    = repairRate,
        upgradeOffer  = upgradeOffer and { cost = upgradeOffer } or nil,
        gunOffer      = gunOffer     and { cost = gunOffer }     or nil,
      }
    else
      state.shipOffer = nil
    end
  else
    state.shipOffer = nil
  end
```

- [ ] **Step 2.8: Add ShipRepair handler**

```lua
Remotes.ShipRepair.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if not state or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.shipOffer or not state.shipOffer.repairRate then return end
  if type(amount) ~= "number" or amount <= 0 then return end

  -- Cap at "All" cost and at cash on hand
  local br      = state.shipOffer.repairRate
  local allCost = ProgressionEngine.repairAllCost(br, state.damage)
  local w       = math.min(amount, allCost, state.cash)

  local repaired = ProgressionEngine.applyRepair(state, br, w)
  if repaired > 0 then
    Remotes.Notify:FireClient(player,
      string.format("Repaired %d damage for $%d, Taipan.", repaired, w))
  end
  -- Refresh repairRate after each repair (re-randomised) and clear if fully repaired
  if state.damage <= 0 then
    state.shipOffer.repairRate = nil
  else
    state.shipOffer.repairRate = ProgressionEngine.repairRate(state)
  end
  pushState(player)
end)
```

- [ ] **Step 2.9: Add AcceptUpgrade handler**

```lua
Remotes.AcceptUpgrade.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.shipOffer or not state.shipOffer.upgradeOffer then return end

  local cost = state.shipOffer.upgradeOffer.cost
  if not ProgressionEngine.applyUpgrade(state, cost) then
    Remotes.Notify:FireClient(player, "You can't afford that, Taipan!")
    pushState(player)
    return
  end
  state.shipOffer.upgradeOffer = nil
  state.shipOffer.repairRate   = nil  -- damage is now 0, no repair needed
  Remotes.Notify:FireClient(player,
    string.format("New ship! Capacity now %d tons, fully repaired!", state.shipCapacity))
  pushState(player)
end)
```

- [ ] **Step 2.10: Add DeclineUpgrade handler**

```lua
Remotes.DeclineUpgrade.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or state.gameOver then return end
  if not state.shipOffer then return end
  state.shipOffer.upgradeOffer = nil
  pushState(player)
end)
```

- [ ] **Step 2.11: Add AcceptGun handler**

```lua
Remotes.AcceptGun.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.shipOffer or not state.shipOffer.gunOffer then return end

  local cost = state.shipOffer.gunOffer.cost
  if not ProgressionEngine.applyGun(state, cost) then
    Remotes.Notify:FireClient(player, "You can't do that, Taipan!")
    pushState(player)
    return
  end
  state.shipOffer.gunOffer = nil
  Remotes.Notify:FireClient(player,
    string.format("Purchased a gun! You now have %d gun(s).", state.guns))
  pushState(player)
end)
```

- [ ] **Step 2.12: Add DeclineGun handler**

```lua
Remotes.DeclineGun.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or state.gameOver then return end
  if not state.shipOffer then return end
  state.shipOffer.gunOffer = nil
  pushState(player)
end)
```

- [ ] **Step 2.13: Add ShipPanelDone handler**

```lua
Remotes.ShipPanelDone.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state then return end
  state.shipOffer = nil
  pushState(player)
end)
```

- [ ] **Step 2.14: Add Retire handler**

```lua
Remotes.Retire.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not ProgressionEngine.canRetire(state) then return end
  Remotes.Notify:FireClient(player, "You've retired as a Taipan!! Well done!!")
  setGameOver(state, "retired")
  pushState(player)
end)
```

- [ ] **Step 2.15: Add QuitGame handler**

```lua
Remotes.QuitGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state or state.gameOver then return end
  setGameOver(state, "quit")
  pushState(player)
end)
```

- [ ] **Step 2.16: Update RestartGame to clear new fields**

The existing `RestartGame` handler creates a fresh state which already has `gameOverReason=nil` etc (from GameState.newGame). No change needed — but verify the handler reads as:

```lua
Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if not state then return end
  if not state.gameOver then return end
  local newState = GameState.newGame("cash")
  newState.currentPrices = PriceEngine.calculatePrices(newState.basePrices, newState.currentPort)
  newState.holdSpace = newState.shipCapacity
  playerStates[player] = newState
  pushState(player)
end)
```

This is unchanged — `GameState.newGame` will include the new fields with nil/false defaults.

- [ ] **Step 2.17: Inject all modified files into Studio (edit mode) and run tests**

Expected: 149+ tests pass (ProgressionEngine tests + prior tests).

- [ ] **Step 2.18: Commit**

```bash
git add src/ReplicatedStorage/shared/GameState.lua \
        src/ReplicatedStorage/Remotes.lua \
        src/ServerScriptService/GameService.server.lua
git commit -m "feat: Phase 6 Task 2 — server handlers for repair/upgrade/gun/retire/quit"
```

---

## Chunk 3: Client — ShipPanel + GameOverPanel + PortPanel

### Task 3: ShipPanel.lua

**Files:**
- Create: `src/StarterGui/TaipanGui/Panels/ShipPanel.lua`
- Modify: `src/StarterGui/TaipanGui/init.client.lua`

---

- [ ] **Step 3.1: Create ShipPanel.lua**

Create `src/StarterGui/TaipanGui/Panels/ShipPanel.lua`:

```lua
-- ShipPanel.lua
-- Modal overlay shown at HK when state.shipOffer ~= nil.
-- Sections: upgrade offer, gun offer, ship repair. DONE dismisses.
-- ZIndex=12 (above normal panels, below CombatPanel=15 and GameOverPanel=20)

local ShipPanel = {}

local AMBER  = Color3.fromRGB(200, 180, 80)
local GREEN  = Color3.fromRGB(140, 200, 80)
local DIM    = Color3.fromRGB(80, 80, 80)
local BG     = Color3.fromRGB(15, 20, 10)
local BORDER = Color3.fromRGB(60, 90, 30)

local function label(parent, name, size, pos, text, color, textSize, zIdx)
  local lbl = Instance.new("TextLabel")
  lbl.Name             = name
  lbl.Size             = size
  lbl.Position         = pos
  lbl.BackgroundTransparency = 1
  lbl.TextColor3       = color or AMBER
  lbl.Font             = Enum.Font.RobotoMono
  lbl.TextSize         = textSize or 14
  lbl.TextXAlignment   = Enum.TextXAlignment.Left
  lbl.TextWrapped      = true
  lbl.ZIndex           = zIdx or 12
  lbl.Text             = text or ""
  lbl.Parent           = parent
  return lbl
end

local function button(parent, name, size, pos, text, bgColor, fgColor, zIdx)
  local btn = Instance.new("TextButton")
  btn.Name             = name
  btn.Size             = size
  btn.Position         = pos
  btn.BackgroundColor3 = bgColor
  btn.BorderColor3     = BORDER
  btn.TextColor3       = fgColor
  btn.Font             = Enum.Font.RobotoMono
  btn.TextSize         = 14
  btn.ZIndex           = zIdx or 12
  btn.Text             = text
  btn.Parent           = parent
  return btn
end

function ShipPanel.new(parent, onRepair, onAcceptUpgrade, onDeclineUpgrade,
                        onAcceptGun, onDeclineGun, onDone)
  local frame = Instance.new("Frame")
  frame.Name               = "ShipPanel"
  frame.Size               = UDim2.new(1, 0, 1, 0)
  frame.Position           = UDim2.new(0, 0, 0, 0)
  frame.BackgroundColor3   = BG
  frame.BackgroundTransparency = 0.05
  frame.BorderSizePixel    = 0
  frame.ZIndex             = 12
  frame.Visible            = false
  frame.Parent             = parent

  local y = 10  -- current vertical cursor

  -- Title
  label(frame, "Title",
    UDim2.new(1, -10, 0, 30), UDim2.new(0, 5, 0, y),
    "[ HONG KONG — SHIP OFFERS ]", AMBER, 16)
  y = y + 36

  -- ── Upgrade section ──────────────────────────────────────────
  local upgradeFrame = Instance.new("Frame")
  upgradeFrame.Name             = "UpgradeFrame"
  upgradeFrame.Size             = UDim2.new(1, -10, 0, 70)
  upgradeFrame.Position         = UDim2.new(0, 5, 0, y)
  upgradeFrame.BackgroundColor3 = Color3.fromRGB(20, 30, 15)
  upgradeFrame.BorderColor3     = BORDER
  upgradeFrame.ZIndex           = 12
  upgradeFrame.Visible          = false
  upgradeFrame.Parent           = frame

  local upgradeLabel = label(upgradeFrame, "UpgradeLabel",
    UDim2.new(1, -10, 0, 40), UDim2.new(0, 5, 0, 5),
    "A merchant offers a larger ship...", AMBER, 13)

  local acceptUpgradeBtn = button(upgradeFrame, "AcceptUpgrade",
    UDim2.new(0.45, 0, 0, 28), UDim2.new(0, 5, 0, 40),
    "UPGRADE", Color3.fromRGB(20, 50, 15), GREEN)
  local declineUpgradeBtn = button(upgradeFrame, "DeclineUpgrade",
    UDim2.new(0.45, 0, 0, 28), UDim2.new(0.5, 5, 0, 40),
    "DECLINE", Color3.fromRGB(40, 20, 10), Color3.fromRGB(180, 100, 60))

  acceptUpgradeBtn.Activated:Connect(onAcceptUpgrade)
  declineUpgradeBtn.Activated:Connect(onDeclineUpgrade)
  y = y + 78

  -- ── Gun section ───────────────────────────────────────────────
  local gunFrame = Instance.new("Frame")
  gunFrame.Name             = "GunFrame"
  gunFrame.Size             = UDim2.new(1, -10, 0, 70)
  gunFrame.Position         = UDim2.new(0, 5, 0, y)
  gunFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
  gunFrame.BorderColor3     = Color3.fromRGB(60, 60, 110)
  gunFrame.ZIndex           = 12
  gunFrame.Visible          = false
  gunFrame.Parent           = frame

  local gunLabel = label(gunFrame, "GunLabel",
    UDim2.new(1, -10, 0, 40), UDim2.new(0, 5, 0, 5),
    "An arms dealer is selling a gun...", AMBER, 13)

  local acceptGunBtn = button(gunFrame, "AcceptGun",
    UDim2.new(0.45, 0, 0, 28), UDim2.new(0, 5, 0, 40),
    "BUY GUN", Color3.fromRGB(20, 20, 50), Color3.fromRGB(120, 120, 220))
  local declineGunBtn = button(gunFrame, "DeclineGun",
    UDim2.new(0.45, 0, 0, 28), UDim2.new(0.5, 5, 0, 40),
    "DECLINE", Color3.fromRGB(40, 20, 10), Color3.fromRGB(180, 100, 60))

  acceptGunBtn.Activated:Connect(onAcceptGun)
  declineGunBtn.Activated:Connect(onDeclineGun)
  y = y + 78

  -- ── Repair section ────────────────────────────────────────────
  local repairFrame = Instance.new("Frame")
  repairFrame.Name             = "RepairFrame"
  repairFrame.Size             = UDim2.new(1, -10, 0, 80)
  repairFrame.Position         = UDim2.new(0, 5, 0, y)
  repairFrame.BackgroundColor3 = Color3.fromRGB(25, 15, 10)
  repairFrame.BorderColor3     = Color3.fromRGB(110, 60, 30)
  repairFrame.ZIndex           = 12
  repairFrame.Visible          = false
  repairFrame.Parent           = frame

  local repairLabel = label(repairFrame, "RepairLabel",
    UDim2.new(1, -10, 0, 20), UDim2.new(0, 5, 0, 4),
    "Ship Repair:", Color3.fromRGB(220, 120, 60), 13)

  local amountBox = Instance.new("TextBox")
  amountBox.Name             = "AmountBox"
  amountBox.Size             = UDim2.new(0.35, 0, 0, 28)
  amountBox.Position         = UDim2.new(0, 5, 0, 30)
  amountBox.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  amountBox.BorderColor3     = Color3.fromRGB(110, 60, 30)
  amountBox.TextColor3       = AMBER
  amountBox.Font             = Enum.Font.RobotoMono
  amountBox.TextSize         = 14
  amountBox.PlaceholderText  = "amount"
  amountBox.ZIndex           = 12
  amountBox.Parent           = repairFrame

  local allBtn = button(repairFrame, "AllBtn",
    UDim2.new(0.2, 0, 0, 28), UDim2.new(0.37, 0, 0, 30),
    "ALL", Color3.fromRGB(40, 25, 10), Color3.fromRGB(200, 150, 60))
  local repairBtn = button(repairFrame, "RepairBtn",
    UDim2.new(0.35, 0, 0, 28), UDim2.new(0.6, 0, 0, 30),
    "REPAIR", Color3.fromRGB(50, 20, 10), Color3.fromRGB(220, 120, 60))

  -- Internal state for "All" cost (updated by update())
  local currentAllCost = 0

  allBtn.Activated:Connect(function()
    amountBox.Text = tostring(currentAllCost)
  end)
  repairBtn.Activated:Connect(function()
    local amt = tonumber(amountBox.Text)
    if amt and amt > 0 then
      onRepair(math.floor(amt))
      amountBox.Text = ""
    end
  end)
  y = y + 88

  -- ── DONE button ───────────────────────────────────────────────
  local doneBtn = button(frame, "DoneBtn",
    UDim2.new(0.4, 0, 0, 36), UDim2.new(0.3, 0, 0, y),
    "DONE", Color3.fromRGB(30, 40, 20), GREEN, 12)
  doneBtn.Activated:Connect(onDone)

  -- ── update() ─────────────────────────────────────────────────
  local panel = {}

  function panel.update(state)
    local offer = state.shipOffer
    frame.Visible = (offer ~= nil and not state.gameOver)

    if not offer then return end

    -- Upgrade section
    if offer.upgradeOffer then
      upgradeFrame.Visible = true
      upgradeLabel.Text = string.format(
        "A merchant offers +50 tons capacity (fully repaired) for $%d!",
        offer.upgradeOffer.cost)
    else
      upgradeFrame.Visible = false
    end

    -- Gun section
    if offer.gunOffer then
      gunFrame.Visible = true
      gunLabel.Text = string.format(
        "An arms dealer offers a cannon for $%d (needs 10 tons hold).",
        offer.gunOffer.cost)
    else
      gunFrame.Visible = false
    end

    -- Repair section
    if offer.repairRate and state.damage > 0 then
      repairFrame.Visible = true
      local br = offer.repairRate
      local sw  = 100 - math.floor(state.damage / state.shipCapacity * 100)
      sw = math.max(0, sw)
      currentAllCost = br * math.ceil(state.damage) + 1
      repairLabel.Text = string.format(
        "Ship Repair: $%d/unit  |  SW: %d%%  |  Damage: %d",
        br, sw, math.floor(state.damage))
    else
      repairFrame.Visible = false
      currentAllCost = 0
    end
  end

  return panel
end

return ShipPanel
```

- [ ] **Step 3.2: Wire ShipPanel into init.client.lua**

Add require at top (with other panel requires):
```lua
local ShipPanel = require(script.Panels.ShipPanel)
```

Add instantiation (with other panel instantiations):
```lua
local shipPanel = ShipPanel.new(root,
  function(amount) Remotes.ShipRepair:FireServer(amount) end,
  function() Remotes.AcceptUpgrade:FireServer() end,
  function() Remotes.DeclineUpgrade:FireServer() end,
  function() Remotes.AcceptGun:FireServer() end,
  function() Remotes.DeclineGun:FireServer() end,
  function() Remotes.ShipPanelDone:FireServer() end
)
```

Add `shipPanel.update(state)` inside the `StateUpdate` handler alongside the other panel updates.

- [ ] **Step 3.3: Inject ShipPanel + updated init.client.lua into Studio**

- [ ] **Step 3.4: Commit**

```bash
git add src/StarterGui/TaipanGui/Panels/ShipPanel.lua \
        src/StarterGui/TaipanGui/init.client.lua
git commit -m "feat: Phase 6 Task 3 — ShipPanel UI (repair/upgrade/gun offers)"
```

---

### Task 4: GameOverPanel + PortPanel + init.client.lua (retire/quit)

**Files:**
- Modify: `src/StarterGui/TaipanGui/Panels/GameOverPanel.lua`
- Modify: `src/StarterGui/TaipanGui/Panels/PortPanel.lua`
- Modify: `src/StarterGui/TaipanGui/init.client.lua`

---

- [ ] **Step 4.1: Extend GameOverPanel to show reason, score, rating**

Replace the hardcoded subtitle text logic with dynamic content:

```lua
function panel.update(state)
  if not state.gameOver then
    frame.Visible = false
    return
  end
  frame.Visible = true

  -- Title color and text by reason
  local reason = state.gameOverReason
  if reason == "retired" then
    title.Text       = "RETIRED!"
    title.TextColor3 = Color3.fromRGB(100, 220, 100)
    frame.BackgroundColor3 = Color3.fromRGB(5, 30, 5)
  elseif reason == "quit" then
    title.Text       = "FAREWELL, TAIPAN"
    title.TextColor3 = Color3.fromRGB(180, 180, 50)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 5)
  else  -- "sunk" or nil (legacy)
    title.Text       = "GAME OVER"
    title.TextColor3 = Color3.fromRGB(220, 50, 50)
    frame.BackgroundColor3 = Color3.fromRGB(30, 5, 5)
  end

  -- Subtitle color matches reason
  if reason == "retired" then
    subtitle.TextColor3 = Color3.fromRGB(100, 220, 100)
  elseif reason == "quit" then
    subtitle.TextColor3 = Color3.fromRGB(200, 190, 80)
  else
    subtitle.TextColor3 = Color3.fromRGB(200, 150, 150)
  end

  -- Subtitle: show score + rating if available
  if state.finalScore ~= nil then
    subtitle.Text = string.format(
      "Score: %d  |  %s", state.finalScore, state.finalRating or "")
  else
    subtitle.Text = reason == "sunk" and "Your ship has sunk, Taipan!"
                 or reason == "quit" and "You have left the trade, Taipan."
                 or "Game over."
  end
end
```

Keep the RESTART button as-is.

- [ ] **Step 4.2: Add RETIRE + QUIT buttons to PortPanel**

At the end of the frame (after port buttons), add:

```lua
  -- RETIRE button (only visible at HK when netWorth >= 1M)
  local retireBtn = Instance.new("TextButton")
  retireBtn.Name             = "RetireBtn"
  retireBtn.Size             = UDim2.new(0.48, 0, 0, 24)
  retireBtn.Position         = UDim2.new(0, 2, 0, 90)  -- below port buttons
  retireBtn.BackgroundColor3 = Color3.fromRGB(20, 50, 15)
  retireBtn.BorderColor3     = Color3.fromRGB(60, 120, 40)
  retireBtn.TextColor3       = Color3.fromRGB(100, 220, 100)
  retireBtn.Font             = Enum.Font.RobotoMono
  retireBtn.TextSize         = 12
  retireBtn.Text             = "RETIRE"
  retireBtn.Visible          = false
  retireBtn.Parent           = frame

  -- QUIT button (always visible)
  local quitBtn = Instance.new("TextButton")
  quitBtn.Name             = "QuitBtn"
  quitBtn.Size             = UDim2.new(0.48, 0, 0, 24)
  quitBtn.Position         = UDim2.new(0.5, 2, 0, 90)
  quitBtn.BackgroundColor3 = Color3.fromRGB(35, 15, 15)
  quitBtn.BorderColor3     = Color3.fromRGB(100, 40, 40)
  quitBtn.TextColor3       = Color3.fromRGB(180, 80, 80)
  quitBtn.Font             = Enum.Font.RobotoMono
  quitBtn.TextSize         = 12
  quitBtn.Text             = "QUIT GAME"
  quitBtn.Parent           = frame

  retireBtn.Activated:Connect(onRetire)
  quitBtn.Activated:Connect(onQuit)
```

Expand the frame height from 90 to 120:
```lua
frame.Size = UDim2.new(1, 0, 0, 120)
```

In `panel.update`, add:
```lua
  -- RETIRE visibility
  local nw = (state.cash or 0) + (state.bankBalance or 0) - (state.debt or 0)
  retireBtn.Visible = (state.currentPort == 1 and nw >= 1000000 and not state.gameOver)
  -- QUIT hidden when game over (GameOverPanel takes over)
  quitBtn.Visible = not state.gameOver
```

Update the PortPanel.new signature to accept `onRetire` and `onQuit`:

```lua
function PortPanel.new(parent, onTravel, onRetire, onQuit)
```

- [ ] **Step 4.3: Adjust all dependent panel positions (+30px cascade)**

PortPanel height increased from 90 to 120px (+30px). Every panel positioned below it must shift +30. Apply these exact changes:

| File | Old y | New y |
|------|-------|-------|
| `StatusStrip.lua` line 11 | `UDim2.new(0,0,0,95)` | `UDim2.new(0,0,0,125)` |
| `InventoryPanel.lua` line 12 | `UDim2.new(0,0,0,130)` | `UDim2.new(0,0,0,160)` |
| `PricesPanel.lua` line 12 | `UDim2.new(0,0,0,255)` | `UDim2.new(0,0,0,285)` |
| `BuySellPanel.lua` line 15 | `UDim2.new(0,0,0,380)` | `UDim2.new(0,0,0,410)` |
| `WarehousePanel.lua` line 17 | `UDim2.new(0,0,0,585)` | `UDim2.new(0,0,0,615)` |
| `WuPanel.lua` line 15 | `UDim2.new(0,0,0,750)` | `UDim2.new(0,0,0,780)` |
| `BankPanel.lua` line 15 | `UDim2.new(0,0,0,980)` | `UDim2.new(0,0,0,1010)` |

Overlay panels (CombatPanel, GameOverPanel, ShipPanel, MessagePanel) are all at y=0 and unaffected.

- [ ] **Step 4.4: Wire retire/quit into init.client.lua**

Update `PortPanel.new` call to pass retire/quit callbacks:

```lua
local portPanel = PortPanel.new(root,
  function(dest) Remotes.TravelTo:FireServer(dest) end,
  function() Remotes.Retire:FireServer() end,
  function() Remotes.QuitGame:FireServer() end
)
```

- [ ] **Step 4.5: Inject all modified files into Studio and smoke-test**

Manual play test checklist:
- [ ] Travel to HK with damaged ship → ShipPanel appears with repair section
- [ ] Repair some damage → cash decreases, damage decreases
- [ ] Repair ALL → damage reaches 0
- [ ] Upgrade offer appears ~25% of trips → UPGRADE adds 50 hold, repairs all
- [ ] Gun offer appears ~33% of trips → BUY GUN adds 1 gun, removes 10 hold
- [ ] RETIRE button visible when net worth ≥ 1M at HK
- [ ] RETIRE fires → game over screen shows score/rating with green "RETIRED!" title
- [ ] QUIT fires → game over screen shows score/rating with "FAREWELL, TAIPAN"
- [ ] Combat sunk → game over screen shows red "GAME OVER" with score/rating
- [ ] RESTART after any game over → fresh game state, no shipOffer, no gameOverReason

- [ ] **Step 4.6: Commit**

```bash
git add src/StarterGui/TaipanGui/Panels/GameOverPanel.lua \
        src/StarterGui/TaipanGui/Panels/PortPanel.lua \
        src/StarterGui/TaipanGui/Panels/StatusStrip.lua \
        src/StarterGui/TaipanGui/Panels/InventoryPanel.lua \
        src/StarterGui/TaipanGui/Panels/PricesPanel.lua \
        src/StarterGui/TaipanGui/Panels/BuySellPanel.lua \
        src/StarterGui/TaipanGui/Panels/WarehousePanel.lua \
        src/StarterGui/TaipanGui/Panels/WuPanel.lua \
        src/StarterGui/TaipanGui/Panels/BankPanel.lua \
        src/StarterGui/TaipanGui/init.client.lua
git commit -m "feat: Phase 6 Task 4 — GameOverPanel score/rating, RETIRE/QUIT buttons, panel positions"
```

---

## Final Verification

- [ ] Run full TestEZ suite — all tests pass (target: 179+ total)
- [ ] Review plan milestone: reach net worth 1,000,000, retire, confirm "Ma Tsu" rating
- [ ] Confirm "Galley Hand" when quitting broke (debt > cash + bank)
