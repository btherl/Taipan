# Wu Warning Scenes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the three-scene Wu braves escort sequence to the Apple II interface, playing after Li Yuen and repair dialogs but before the Wu question.

**Architecture:** Store the braves count as `state.wuEscortBraves` at arrival time. A new helper `injectWuEscortIfReady` inserts three `pendingMessages` entries into any push where both `liYuenPending` and `repairPending` are false and `wuPending` is true. Called at five push sites in `GameService`.

**Tech Stack:** Luau, Roblox RemoteEvents, `pendingMessages` notification queue (already in use).

---

## Files

| File | Change |
|---|---|
| `sync/ServerScriptService/GameService.server.luau` | Only file modified. Add helper, store braves count, call helper at 5 push sites. |

---

### Task 1: Add `injectWuEscortIfReady` helper

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau:52` (after `makeCompradorNotif`)

- [ ] **Step 1: Insert the helper after `makeCompradorNotif` (after line 51)**

Insert these lines after line 51 (the closing `end` of `makeCompradorNotif`):

```lua
-- Injects the three Wu escort notifications into pendingTable when all of
-- liYuenPending, repairPending are resolved and wuPending is active.
-- Clears wuEscortBraves after injecting so the scenes only play once.
-- Safe to call even when conditions are not yet met — does nothing.
local function injectWuEscortIfReady(state, pendingTable)
  if not state.wuEscortBraves then return end
  if state.liYuenPending or state.repairPending then return end
  if not state.wuPending then return end
  local N = state.wuEscortBraves
  state.wuEscortBraves = nil
  table.insert(pendingTable, makeCompradorNotif({
    string.format("Elder Brother Wu has sent %d braves", N),
    "to escort you to the Wu mansion, Taipan.",
  }, 5))
  table.insert(pendingTable, makeCompradorNotif({
    "Elder Brother Wu reminds you of the",
    "Confucian ideal of personal worthiness,",
    "and how this applies to paying one's",
    "debts.",
  }, 10))
  table.insert(pendingTable, makeCompradorNotif({
    "He is reminded of a fabled barbarian",
    "who came to a bad end, after not caring",
    "for his obligations.",
    "",
    "He hopes no such fate awaits you, his",
    "friend, Taipan.",
  }, 10))
end
```

- [ ] **Step 2: Verify the file still parses (no syntax errors)**

Check that Studio or the Luau LSP shows no errors on the file. No runtime test yet.

---

### Task 2: Store braves count in TravelTo; remove old Notify

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau:253-258`

- [ ] **Step 1: Replace the braves Notify block**

Find this block (lines 253–258):

```lua
      local braves = FinanceEngine.wuWarningCheck(state)
      if braves then
        Remotes.Notify:FireClient(player,
          string.format("ELDER BROTHER WU has heard of your debt! He is sending %d braves to collect!", braves))
      end
```

Replace with:

```lua
      local braves = FinanceEngine.wuWarningCheck(state)
      if braves then
        state.wuEscortBraves = braves
      end
```

- [ ] **Step 2: Call `injectWuEscortIfReady` in TravelTo before the final push**

Find this block near line 384:

```lua
  state.pendingMessages = pending
  pushState(player)
  state.pendingMessages = nil
```

Replace with:

```lua
  injectWuEscortIfReady(state, pending)
  state.pendingMessages = pending
  pushState(player)
  state.pendingMessages = nil
```

- [ ] **Step 3: Verify no syntax errors in the file**

---

### Task 3: Inject escort in Li Yuen handlers

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau:465-482`

- [ ] **Step 1: Update `BuyLiYuenProtection.OnServerEvent`**

Find (lines 465–473):

```lua
Remotes.BuyLiYuenProtection.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not FinanceEngine.buyLiYuenProtection(state) then pushState(player) return end
  state.liYuenPending = false
  Remotes.Notify:FireClient(player, "Li Yuen smiles. You are under his protection.")
  pushState(player)
end)
```

Replace with:

```lua
Remotes.BuyLiYuenProtection.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not FinanceEngine.buyLiYuenProtection(state) then pushState(player) return end
  state.liYuenPending = false
  Remotes.Notify:FireClient(player, "Li Yuen smiles. You are under his protection.")
  local msgs = {}
  injectWuEscortIfReady(state, msgs)
  state.pendingMessages = #msgs > 0 and msgs or nil
  pushState(player)
  state.pendingMessages = nil
end)
```

- [ ] **Step 2: Update `DeclineLiYuenTribute.OnServerEvent`**

Find (lines 475–482):

```lua
Remotes.DeclineLiYuenTribute.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  state.liYuenPending   = false
  state.liYuenOfferCost = nil
  pushState(player)
end)
```

Replace with:

```lua
Remotes.DeclineLiYuenTribute.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  state.liYuenPending   = false
  state.liYuenOfferCost = nil
  local msgs = {}
  injectWuEscortIfReady(state, msgs)
  state.pendingMessages = #msgs > 0 and msgs or nil
  pushState(player)
  state.pendingMessages = nil
end)
```

- [ ] **Step 3: Verify no syntax errors**

---

### Task 4: Inject escort in repair handlers

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau:776-804`

- [ ] **Step 1: Update `ShipRepair.OnServerEvent`**

Find (lines 776–794):

```lua
Remotes.ShipRepair.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.shipOffer or not state.shipOffer.repairRate then return end
  if type(amount) ~= "number" or amount <= 0 then return end
  local br      = state.shipOffer.repairRate
  local allCost = ProgressionEngine.repairAllCost(br, state.damage)
  local w       = math.min(amount, allCost, state.cash)
  local repaired = ProgressionEngine.applyRepair(state, br, w)
  if repaired > 0 then
    Remotes.Notify:FireClient(player,
      string.format("Repaired %d damage for $%d, Taipan.", repaired, w))
  end
  state.shipOffer.repairRate = nil
  state.repairPending = false
  cleanupShipOffer(state)
  pushState(player)
end)
```

Replace with:

```lua
Remotes.ShipRepair.OnServerEvent:Connect(function(player, amount)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if not state.shipOffer or not state.shipOffer.repairRate then return end
  if type(amount) ~= "number" or amount <= 0 then return end
  local br      = state.shipOffer.repairRate
  local allCost = ProgressionEngine.repairAllCost(br, state.damage)
  local w       = math.min(amount, allCost, state.cash)
  local repaired = ProgressionEngine.applyRepair(state, br, w)
  if repaired > 0 then
    Remotes.Notify:FireClient(player,
      string.format("Repaired %d damage for $%d, Taipan.", repaired, w))
  end
  state.shipOffer.repairRate = nil
  state.repairPending = false
  cleanupShipOffer(state)
  local msgs = {}
  injectWuEscortIfReady(state, msgs)
  state.pendingMessages = #msgs > 0 and msgs or nil
  pushState(player)
  state.pendingMessages = nil
end)
```

- [ ] **Step 2: Update `DeclineRepair.OnServerEvent`**

Find (lines 796–804):

```lua
Remotes.DeclineRepair.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if state.shipOffer then state.shipOffer.repairRate = nil end
  state.repairPending = false
  cleanupShipOffer(state)
  pushState(player)
end)
```

Replace with:

```lua
Remotes.DeclineRepair.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  if state.shipOffer then state.shipOffer.repairRate = nil end
  state.repairPending = false
  cleanupShipOffer(state)
  local msgs = {}
  injectWuEscortIfReady(state, msgs)
  state.pendingMessages = #msgs > 0 and msgs or nil
  pushState(player)
  state.pendingMessages = nil
end)
```

- [ ] **Step 3: Verify no syntax errors**

---

### Task 5: Commit

- [ ] **Step 1: Commit the change**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "feat: add Wu braves escort scenes to Apple II notification queue"
```

---

### Task 6: Playtest verification (MCP)

Verify the sequence plays correctly via MCP playtesting. Studio must be stopped before injecting, running after.

- [ ] **Step 1: Start Play mode**

Use `start_stop_play(is_start: true)`.

- [ ] **Step 2: Set up a state with debt > $10,000, wuWarningGiven=false**

```lua
-- execute_luau (client-side, fires server remote)
local Remotes = require(game:GetService("ReplicatedStorage").Remotes)
-- Start a new cash game to get debt=5000, then travel a few times won't help.
-- Easier: use RequestStateUpdate to inspect state, then manually set via a test helper.
-- Alternatively: start a guns game (no debt) and verify escort does NOT fire.
-- Then start a cash game and borrow enough from Wu to exceed 10000 debt.
Remotes.ChooseStart:FireServer("cash", "TestFirm")
```

- [ ] **Step 3: Borrow from Wu to push debt above $10,000**

Travel to HK (already there on start). Visit Wu, borrow enough to exceed $10,000 total debt (start debt is $5,000 — borrow $6,000 more).

- [ ] **Step 4: Travel away from HK and return**

Travel to any other port (e.g. port 2 Shanghai), then travel back to HK (port 1).

- [ ] **Step 5: Capture screen and confirm escort sequence**

Use `screen_capture` after each notification to confirm:
1. "Elder Brother Wu has sent N braves / to escort you to the Wu mansion, Taipan." (5 sec)
2. "Elder Brother Wu reminds you of the Confucian ideal..." (10 sec)
3. "He is reminded of a fabled barbarian..." (10 sec)
4. After all three: Wu question dialog appears ("Do you have business with Elder Brother Wu?")

- [ ] **Step 6: Confirm escort does NOT replay on a second HK visit**

Travel away and back again. The escort should not appear (wuWarningGiven=true, wuEscortBraves=nil).

- [ ] **Step 7: Stop Play mode**

Use `start_stop_play(is_start: false)`.
