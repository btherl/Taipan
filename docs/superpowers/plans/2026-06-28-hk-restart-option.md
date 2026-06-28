# HK Restart (Abandon Ship) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a player-facing "Restart" (abandon ship) option to the Hong Kong port menu that ends the game via the existing score screen and loops back to the firm-name lobby.

**Architecture:** Client-side menu/scene work in `PromptEngine.luau` (the Apple II prompt engine, unit-testable via the TestEZ `PromptEngine/spec.luau`), plus a thin server `AbandonShip` remote handler that reuses the existing `setGameOver` helper with a new `"abandoned"` reason. The score screen (`sceneFinalStatus`) and its "Play again?" → `restartGame` loop are reused unchanged.

**Tech Stack:** Roblox Luau, TestEZ (Studio Run mode only), Azul file sync, MCP Studio playtest.

## Global Constraints

- **Interface:** Apple II terminal only. Do not touch the Modern interface panels.
- **Availability:** Hong Kong (`currentPort == HONG_KONG`) only, and only when **not** retire-eligible (net worth `cash + bankBalance - debt < 1000000`). Restart and Retire share the **R** key and the same screen slot; never shown together.
- **Exact copy (verbatim):**
  - Menu row 24: `cargo, Quit trading, or Restart?`
  - Confirmation (displayed across two rows; 40-col limit): `Do you wish to abandon your ship,` + `Taipan? (Y/N)`
  - Abandon message (displayed across two rows; 40-col limit): `Ashamed of your failure, you disappear` + `into the night, never to be seen again.`
- **Server guard for `AbandonShip`:** state is a table, `not state.gameOver`, `currentPort == Constants.HONG_KONG`. No wealth check.
- **`gameOverReason` value:** `"abandoned"` (string, exact).
- **Reuse, don't fork:** the abandon flow ends at the existing `sceneFinalStatus`; do not modify its content or the "Play again?" loop.
- **Testing reality:** TestEZ runs **only in Studio Run mode** (`RunService:IsRunMode()`). MCP cannot trigger the suite. Every "run the test" step means: in Roblox Studio click **Run** (not Play), read the **Output** panel — ask the user to do this and paste the result. Server-script and end-to-end behaviour is verified by MCP playtest (Task 5), not TestEZ.
- **Azul sync:** local `.luau` edits propagate to Studio automatically; no manual copy step.

---

### Task 1: Port menu shows "Restart" when not retire-eligible

Add the Restart option to the Hong Kong port menu's non-retire branch, sharing the **R** key with Retire. Pressing **R** routes to a (not-yet-existing) `restart_confirm` sub-scene; until Task 2 that route is inert at runtime, which is safe.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (function `sceneAtPort`, ~lines 347–394)
- Test: `sync/ServerScriptService/Tests/PromptEngine/spec.luau`

**Interfaces:**
- Consumes: `PromptEngine.processState(state, localScene, actions, localSceneCb)` returning `(lines, promptDef)`; `promptDef.keys` (array), `promptDef.onKey(key, state, actions)`, `lines.rows[n].text`.
- Produces: at Hong Kong with net worth `< 1000000`, `lines.rows[24].text == "cargo, Quit trading, or Restart?"`, `promptDef.keys` contains `"R"`, and `promptDef.onKey("R", ...)` calls `localSceneCb("restart_confirm")`. At net worth `>= 1000000` the menu is unchanged (`...or Retire?`, `onKey("R")` calls `actions.retire()`).

- [ ] **Step 1: Write the failing tests**

Add this `describe` block inside the `return function() ... end` in `sync/ServerScriptService/Tests/PromptEngine/spec.luau` (e.g. after the existing combat block):

```lua
  describe("PromptEngine HK Restart option", function()
    local function hkState(netWorth)
      -- cash carries the whole net worth; debt/bank zero.
      -- startChoice set so processState routes to sceneAtPort, not the
      -- new-game firm-name branch (which fires when startChoice == nil).
      return {
        currentPort = 1, gameOver = false, startChoice = "cash",
        cash = netWorth, bankBalance = 0, debt = 0,
        currentPrices = {1,2,3,4},
        shipCargo = {0,0,0,0}, warehouseCargo = {0,0,0,0},
        holdSpace = 60, shipCapacity = 60, guns = 0,
      }
    end

    it("shows Restart (not Retire) at HK when net worth < 1,000,000", function()
      local lines, promptDef = PromptEngine.processState(hkState(500000), nil, mockActions(), function() end)
      expect(lines.rows[24].text).to.equal("cargo, Quit trading, or Restart?")
      local keySet = {}
      for _, k in ipairs(promptDef.keys) do keySet[k] = true end
      expect(keySet["R"]).to.equal(true)
    end)

    it("routes R to restart_confirm when not retire-eligible", function()
      local routed
      local promptDef = select(2, PromptEngine.processState(
        hkState(500000), nil, mockActions(), function(scene) routed = scene end))
      promptDef.onKey("R", hkState(500000), mockActions())
      expect(routed).to.equal("restart_confirm")
    end)

    it("still shows Retire and calls retire() when net worth >= 1,000,000", function()
      local retired = false
      local actions = mockActions(); actions.retire = function() retired = true end
      local lines, promptDef = PromptEngine.processState(hkState(1000000), nil, actions, function() end)
      expect(lines.rows[24].text).to.equal("cargo, Quit trading, or Retire?")
      promptDef.onKey("R", hkState(1000000), actions)
      expect(retired).to.equal(true)
    end)
  end)
```

- [ ] **Step 2: Run the tests to verify they fail**

In Roblox Studio click **Run** (not Play); read Output. (MCP cannot trigger TestEZ — ask the user to click Run and paste Output.)
Expected: the first two new tests FAIL — row 24 reads `cargo, or Quit trading?` and `R` is not in `keys`/routes nowhere. The third (Retire) test PASSES.

- [ ] **Step 3: Implement the menu + key + routing change**

In `PromptEngine.luau` `sceneAtPort`, replace the HK non-retire branch (currently):

```lua
    else
      rows[23] = { text = "Shall I Buy, Sell, Visit bank, Transfer",  color = GREEN }
      rows[24] = { text = "cargo, or Quit trading?",                  color = GREEN }
      table.insert(validKeys, "V")
      table.insert(validKeys, "T")
      cursorRow    = 24
      cursorPrefix = "cargo, or Quit trading? "
    end
```

with:

```lua
    else
      rows[23] = { text = "Shall I Buy, Sell, Visit bank, Transfer",  color = GREEN }
      rows[24] = { text = "cargo, Quit trading, or Restart?",         color = GREEN }
      table.insert(validKeys, "V")
      table.insert(validKeys, "T")
      table.insert(validKeys, "R")
      cursorRow    = 24
      cursorPrefix = "cargo, Quit trading, or Restart? "
    end
```

Then in the same function's `onKey`, replace the existing `R` handler (currently):

```lua
      elseif key == "R" then
        actions.retire()
      end
```

with (branch on the `canRetire` upvalue already computed at the top of `sceneAtPort`):

```lua
      elseif key == "R" then
        if canRetire then
          actions.retire()
        elseif localSceneCb then
          localSceneCb("restart_confirm")
        end
      end
```

- [ ] **Step 4: Run the tests to verify they pass**

In Studio click **Run**; read Output. Expected: all three HK-Restart tests PASS, and no previously-passing test regresses.

- [ ] **Step 5: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau sync/ServerScriptService/Tests/PromptEngine/spec.luau
git commit -m "Show Restart in HK port menu when not retire-eligible"
```

---

### Task 2: Restart confirmation scene + abandon plumbing

Add the `AbandonShip` remote, its client action wrapper, and the `sceneRestartConfirm` confirmation. **Y** fires `abandonShip`; **N** returns to the port menu.

**Files:**
- Modify: `sync/ReplicatedStorage/Remotes.luau` (add `AbandonShip`)
- Modify: `sourcemap.json` (register the `AbandonShip` RemoteEvent instance)
- Modify: `sync/StarterGui/TaipanGui/GameController/GameActions.luau` (add `abandonShip` wrapper)
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (add `sceneRestartConfirm`; route `localScene == "restart_confirm"`)
- Test: `sync/ServerScriptService/Tests/PromptEngine/spec.luau` (add `abandonShip` to `mockActions`; new tests)

**Interfaces:**
- Consumes: `localSceneCb` from Task 1's `onKey("R")` call (the value `"restart_confirm"`); `actions.abandonShip()`.
- Produces: `Remotes.AbandonShip` (RemoteEvent); `GameActions.abandonShip()` → `Remotes.AbandonShip:FireServer()`; `processState(..., "restart_confirm", ...)` returns a `promptDef` with `keys == {"Y","N"}` whose `onKey("Y")` calls `actions.abandonShip()` and `onKey("N")` calls `localSceneCb(nil)`; the confirmation line text is `Do you wish to abandon your ship, Taipan? (Y/N)`.

- [ ] **Step 1: Add the `AbandonShip` remote**

In `sync/ReplicatedStorage/Remotes.luau`, in the "Phase 6" group (next to `Retire`/`QuitGame`, ~line 60) add:

```lua
Remotes.AbandonShip    = getOrCreate("RemoteEvent", "AbandonShip")    -- client->server: abandon ship at HK (restart)
```

In `sourcemap.json`, add a child to the `ReplicatedStorage` `children` array (alphabetical order — before `AcceptGun` at line 47). Guid `11200` is currently unused:

```json
        {
          "name": "AbandonShip",
          "className": "RemoteEvent",
          "guid": "11200"
        },
```

- [ ] **Step 2: Add the client action wrapper**

In `sync/StarterGui/TaipanGui/GameController/GameActions.luau`, next to `retire`/`quitGame`/`restartGame` (~lines 39–41) add:

```lua
  abandonShip    = function()       Remotes.AbandonShip:FireServer() end,
```

- [ ] **Step 3: Write the failing tests**

In `sync/ServerScriptService/Tests/PromptEngine/spec.luau`, first add `abandonShip` to `mockActions` (so confirm-scene tests can spy on it). Inside the `mockActions` table literal add:

```lua
    abandonShip = function() end,
```

Then add this `describe` block inside `return function() ... end`:

```lua
  describe("PromptEngine sceneRestartConfirm", function()
    local function hkState()
      -- startChoice set so processState does not route to the new-game
      -- firm-name branch (which fires when startChoice == nil).
      return {
        currentPort = 1, gameOver = false, startChoice = "cash",
        cash = 500000, bankBalance = 0, debt = 0,
        currentPrices = {1,2,3,4},
        shipCargo = {0,0,0,0}, warehouseCargo = {0,0,0,0},
        holdSpace = 60, shipCapacity = 60, guns = 0,
      }
    end

    it("renders the abandon confirmation prompt", function()
      local lines, promptDef = PromptEngine.processState(hkState(), "restart_confirm", mockActions(), function() end)
      local l1, l2 = false, false
      for _, row in pairs(lines.rows) do
        if row.text == "Do you wish to abandon your ship," then l1 = true end
        if row.text == "Taipan? (Y/N)" then l2 = true end
      end
      expect(l1).to.equal(true)
      expect(l2).to.equal(true)
      local keySet = {}
      for _, k in ipairs(promptDef.keys) do keySet[k] = true end
      expect(keySet["Y"]).to.equal(true)
      expect(keySet["N"]).to.equal(true)
    end)

    it("Y calls abandonShip()", function()
      local called = false
      local actions = mockActions(); actions.abandonShip = function() called = true end
      local promptDef = select(2, PromptEngine.processState(hkState(), "restart_confirm", actions, function() end))
      promptDef.onKey("Y", hkState(), actions)
      expect(called).to.equal(true)
    end)

    it("N returns to the port menu via localSceneCb(nil)", function()
      local routedToNil = false
      local promptDef = select(2, PromptEngine.processState(
        hkState(), "restart_confirm", mockActions(),
        function(scene) if scene == nil then routedToNil = true end end))
      promptDef.onKey("N", hkState(), mockActions())
      expect(routedToNil).to.equal(true)
    end)
  end)
```

- [ ] **Step 4: Run the tests to verify they fail**

In Studio click **Run**; read Output. Expected: the three `sceneRestartConfirm` tests FAIL (scene not routed — falls through to `sceneAtPort`, so the confirmation line is absent and `keys` are the port keys).

- [ ] **Step 5: Implement `sceneRestartConfirm` and route it**

In `PromptEngine.luau`, add this function immediately after `sceneQuitConfirm` (which ends ~line 578):

```lua
local function sceneRestartConfirm(_state, actions, localSceneCb)
  local rows = {}
  for r = 1, 24 do rows[r] = { text = "", color = AMBER } end
  -- Split across two rows: the full sentence is 47 chars, over the 40-column
  -- terminal width that every other prompt respects.
  rows[22] = { text = "Do you wish to abandon your ship,", color = AMBER }
  rows[23] = { text = "Taipan? (Y/N)",                     color = AMBER }
  return { rows = rows }, {
    type  = "key",
    keys  = {"Y", "N"},
    label = "Do you wish to abandon your ship, Taipan? (Y/N)",
    onKey = function(key, _s, _a)
      if key == "Y" then
        actions.abandonShip()
      elseif key == "N" then
        if localSceneCb then localSceneCb(nil) end
      end
    end,
  }
end
```

Then add the route next to the `quit_confirm` route (line 1621), before the firm-name fallthrough:

```lua
  if localScene == "restart_confirm" then return sceneRestartConfirm(state, actions, localSceneCb) end
```

- [ ] **Step 6: Run the tests to verify they pass**

In Studio click **Run**; read Output. Expected: all three `sceneRestartConfirm` tests PASS; Task 1 tests still PASS.

- [ ] **Step 7: Commit**

```bash
git add sync/ReplicatedStorage/Remotes.luau sourcemap.json sync/StarterGui/TaipanGui/GameController/GameActions.luau sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau sync/ServerScriptService/Tests/PromptEngine/spec.luau
git commit -m "Add abandon-ship confirmation scene and AbandonShip remote"
```

---

### Task 3: Server `AbandonShip` handler

Wire the server to end the game with `gameOverReason = "abandoned"` when the client fires `AbandonShip` at Hong Kong. This is a server `Script` — **not** TestEZ-testable; it is verified by the Task 5 playtest and by code review.

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau` (add handler near the `QuitGame` handler, ~line 1118)

**Interfaces:**
- Consumes: `Remotes.AbandonShip` (Task 2); existing `playerStates`, `setGameOver(state, reason)`, `pushState(player)`, `Constants.HONG_KONG`.
- Produces: on a valid fire, `state.gameOver == true` and `state.gameOverReason == "abandoned"` with `finalScore`/`finalRating` populated by `setGameOver`.

- [ ] **Step 1: Implement the handler**

In `GameService.server.luau`, immediately after the `Remotes.QuitGame.OnServerEvent` handler (ends ~line 1118) add:

```lua
Remotes.AbandonShip.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or state.gameOver then return end
  if state.currentPort ~= Constants.HONG_KONG then return end
  setGameOver(state, "abandoned")
  pushState(player)
end)
```

- [ ] **Step 2: Verify it loads (no syntax error)**

In Studio click **Run**; read Output. Expected: no load/parse error from `GameService` (TestEZ output appears as usual; the handler itself runs no tests). Ask the user to confirm Output is clean.

- [ ] **Step 3: Commit**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "Add server AbandonShip handler (gameOverReason abandoned)"
```

---

### Task 4: Abandon message scene + "abandoned" score routing

Render the abandon "failure" message and then route into the existing score screen.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (add `sceneAbandonMessage`; add `"abandoned"` branch to `processState`'s game-over block, ~lines 1514–1527)
- Test: `sync/ServerScriptService/Tests/PromptEngine/spec.luau`

**Interfaces:**
- Consumes: existing `sceneFinalStatus(state, actions, localSceneCb)`; the game-over routing block in `processState`.
- Produces: with `gameOver == true`, `gameOverReason == "abandoned"`, and `localScene == nil`, `processState` returns the abandon message split across two rows (`Ashamed of your failure, you disappear` and `into the night, never to be seen again.`, each ≤ 40 columns) and a `promptDef` with `anyKey == true` whose `onKey()` calls `localSceneCb("final_status")`. With `localScene == "final_status"` it returns `sceneFinalStatus` (rows contain `Your final status:`).

- [ ] **Step 1: Write the failing tests**

In `sync/ServerScriptService/Tests/PromptEngine/spec.luau` add inside `return function() ... end`:

```lua
  describe("PromptEngine abandon flow", function()
    local function abandonedState()
      return {
        gameOver = true, gameOverReason = "abandoned",
        finalScore = 42, finalRating = "Galley Hand",
        cash = 1000, bankBalance = 0, debt = 0,
        shipCapacity = 60, guns = 0, turnsElapsed = 3,
        month = 4, year = 1860, currentPort = 1, damage = 0,
        shipCargo = {0,0,0,0}, warehouseCargo = {0,0,0,0}, warehouseUsed = 0,
        holdSpace = 60,
      }
    end

    it("shows the abandon message first, then advances to final_status", function()
      local routed
      local lines, promptDef = PromptEngine.processState(
        abandonedState(), nil, mockActions(), function(scene) routed = scene end)
      local line1, line2 = false, false
      for _, row in pairs(lines.rows) do
        if row.text == "Ashamed of your failure, you disappear" then line1 = true end
        if row.text == "into the night, never to be seen again." then line2 = true end
      end
      expect(line1).to.equal(true)
      expect(line2).to.equal(true)
      expect(promptDef.anyKey).to.equal(true)
      promptDef.onKey("X", abandonedState(), mockActions())
      expect(routed).to.equal("final_status")
    end)

    it("routes to the score screen at localScene final_status", function()
      local lines = PromptEngine.processState(abandonedState(), "final_status", mockActions(), function() end)
      local found = false
      for _, row in pairs(lines.rows) do
        if row.text == "Your final status:" then found = true end
      end
      expect(found).to.equal(true)
    end)
  end)
```

- [ ] **Step 2: Run the tests to verify they fail**

In Studio click **Run**; read Output. Expected: both abandon-flow tests FAIL — `"abandoned"` is unhandled, so `processState` falls through the game-over block to `sceneGameOver` ("GAME OVER"), with no abandon message and no `final_status` routing.

- [ ] **Step 3: Implement the message scene and routing**

In `PromptEngine.luau`, add this function just before `sceneGameOver` (~line 540). The message is split across two rows because the terminal is 40 columns wide and the full sentence is 76 characters; each half is ≤ 40 columns:

```lua
local function sceneAbandonMessage(_state, _actions, localSceneCb)
  local rows = {}
  for r = 1, 24 do rows[r] = { text = "", color = AMBER } end
  rows[11] = { text = "Ashamed of your failure, you disappear", color = AMBER }
  rows[12] = { text = "into the night, never to be seen again.", color = AMBER }
  return { rows = rows }, {
    type   = "key",
    keys   = {},
    anyKey = true,
    onKey  = function()
      if localSceneCb then localSceneCb("final_status") end
    end,
  }
end
```

Then in `processState`'s game-over block, add an `elseif` branch (after the `"sunk"` branch, before the final `return sceneGameOver(...)`):

```lua
    elseif state.gameOverReason == "abandoned" then
      if localScene == "final_status" then
        return sceneFinalStatus(state, actions, localSceneCb)
      end
      return sceneAbandonMessage(state, actions, localSceneCb)
```

- [ ] **Step 4: Run the tests to verify they pass**

In Studio click **Run**; read Output. Expected: both abandon-flow tests PASS; all earlier tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau sync/ServerScriptService/Tests/PromptEngine/spec.luau
git commit -m "Route abandoned game-over through message scene to score screen"
```

---

### Task 5: End-to-end MCP playtest verification

Verify the full chain at runtime (server + client wiring that TestEZ cannot cover). No code unless a defect is found.

**Files:** none (verification only).

**Interfaces:** Consumes the complete feature from Tasks 1–4.

- [ ] **Step 1: Enter Play mode and start a game at Hong Kong**

Use MCP: `start_stop_play(is_start: true)`. Select the Apple II interface, enter a firm name, choose a start. Confirm you are at Hong Kong (port 1).

- [ ] **Step 2: Verify the menu shows Restart**

`screen_capture`. Expected: the port prompt row reads `cargo, Quit trading, or Restart?` (net worth is far below $1,000,000 at game start).

- [ ] **Step 3: Trigger Restart and confirm the confirmation prompt**

`user_keyboard_input` → `R`. `screen_capture`. Expected: `Do you wish to abandon your ship, Taipan? (Y/N)`.

- [ ] **Step 4: Verify N cancels**

`user_keyboard_input` → `N`. `screen_capture`. Expected: back at the Hong Kong port menu.

- [ ] **Step 5: Verify Y → message → score → firm name loop**

`R`, then `Y`. `screen_capture` — expect the two-line message `Ashamed of your failure, you disappear` / `into the night, never to be seen again.`. Press any key; `screen_capture` — expect the score screen (`Your final status:` … `Play again?`). Press `Y`; `screen_capture` — expect the firm-name screen.

- [ ] **Step 6: Verify server state (optional sanity)**

Via `execute_luau`, connect `Remotes.StateUpdate.OnClientEvent` and fire `RequestStateUpdate`; after pressing Restart→Y (before "Play again?"), confirm the captured state has `gameOver == true` and `gameOverReason == "abandoned"`.

- [ ] **Step 7: Exit play mode**

`start_stop_play(is_start: false)`. Report results. If all steps pass, the feature is complete; if any step fails, switch to systematic-debugging before changing code.

---

## Notes for the implementer

- `AMBER`, `GREEN`, `HONG_KONG`, `sceneFinalStatus`, `sceneQuitConfirm`, `sceneGameOver`, `setGameOver`, `pushState`, `Constants` are all already defined/required in their respective files — do not re-declare them.
- Do not modify `sceneFinalStatus` or the "Play again?" handler; the abandon flow reuses them as-is.
- After Task 1's commit, **R** is intentionally inert at runtime until Task 2 routes `restart_confirm`; this is expected and safe (mirrors prior sequenced-dependency commits in this codebase).
