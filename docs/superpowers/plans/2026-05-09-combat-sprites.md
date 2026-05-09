# Combat Sprites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the 10-slot enemy-ship sprite grid in the Apple II combat scene with hit-flash, damage-fragment overlay, instant flee blank, and random-speed sink animation, driven by a server-side event timeline.

**Architecture:** Server-side `CombatEngine` appends typed events (`hit`/`sink`/`spawn`/`flee`) to a `combat.events` list during `fight`/`partialEscape`. `GameService` resets the list at each combat-action handler entry and includes it in the state push. Client-side, a new `Apple2/ShipGrid` module owns 10 slot Frames (each with `ClipsDescendants=true`) populated with `ImageLabel`-based glyphs from the existing `TaipanThickFont` atlas. `Apple2Interface` drains the event list sequentially through `ShipGrid`, gating the round prompt while animations play.

**Tech Stack:** Luau, Roblox UI (Frames + ImageLabels), TweenService, TestEZ for engine tests, MCP playtest for GUI verification.

**Reference docs:**
- Spec: `docs/superpowers/specs/2026-05-09-combat-sprites-design.md`
- Original analysis: `docs/original_design/COMBAT_SPRITES.md`
- BASIC source: `references/taipan-applesoft-annotated.txt` lines 5320–5895, 5800–5895, 10250–10300

---

## File Inventory

**New files:**
- `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau` — GUI layer: slot frames, glyph rendering, animations.
- `sync/StarterGui/TaipanGui/GameController/Apple2/ShipSpriteData.luau` — Pure data module: base sprite, damage fragment tables, `applyDamageFragment` helper.
- `sync/ServerScriptService/Tests/ShipSpriteData.spec.luau` — Unit tests for the pure data module.

**Modified files:**
- `sync/ReplicatedStorage/shared/CombatEngine.luau` — `fight`, `partialEscape` append to `combat.events`.
- `sync/ServerScriptService/GameService.server.luau` — `CombatFight`/`CombatRun`/`CombatThrow`/`CombatNoCommand` handlers reset `state.combat.events = {}` at entry and clear it after `pushState`.
- `sync/ServerScriptService/Tests/CombatEngine.spec.luau` — New `describe("events", ...)` block.
- `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` — Instantiate `ShipGrid`, drain events sequentially, gate `startRoundIfCombat` on animation, show/hide on combat boundaries.
- `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` — Remove the `"  Ships: [#.##.....#]"` placeholder from `sceneCombatLayout`.

---

## Phase 1 — Server-side event timeline

### Task 1: `CombatEngine.fight` appends `hit` and `sink` events

**Files:**
- Modify: `sync/ReplicatedStorage/shared/CombatEngine.luau` (function `fight`, ~lines 101–180)
- Test: `sync/ServerScriptService/Tests/CombatEngine.spec.luau` (append a new `describe` block)

- [ ] **Step 1: Write failing tests for hit/sink events**

Append at the very end of `CombatEngine.spec.luau`, just before the final `end` of the outer `return function()`:

```lua
  describe("fight events", function()
    it("appends hit events for non-killing shots", function()
      local s = makeState({ guns = 1, enemyBaseHP = 10000 })
      local c = CombatEngine.initCombat(s, 1, 1)
      c.grid[3] = { maxHP = 10000, damage = 0 }
      c.enemyOnScreen = 1
      c.enemyWaiting  = 0
      c.events = {}
      CombatEngine.fight(s, c)
      expect(#c.events).to.equal(1)
      expect(c.events[1].type).to.equal("hit")
      expect(c.events[1].slot).to.equal(3)
    end)

    it("appends a sink event immediately after a killing hit on the same slot", function()
      local s = makeState({ guns = 1, enemyBaseHP = 1 })
      local c = CombatEngine.initCombat(s, 1, 1)
      c.grid[5] = { maxHP = 1, damage = 0 }
      c.enemyOnScreen = 1
      c.enemyWaiting  = 0
      c.events = {}
      CombatEngine.fight(s, c)
      expect(#c.events).to.equal(2)
      expect(c.events[1].type).to.equal("hit")
      expect(c.events[1].slot).to.equal(5)
      expect(c.events[2].type).to.equal("sink")
      expect(c.events[2].slot).to.equal(5)
    end)

    it("auto-initialises events list if absent", function()
      local s = makeState({ guns = 1, enemyBaseHP = 10000 })
      local c = CombatEngine.initCombat(s, 1, 1)
      c.grid[1] = { maxHP = 10000, damage = 0 }
      c.enemyOnScreen = 1
      c.enemyWaiting  = 0
      -- deliberately do NOT set c.events
      CombatEngine.fight(s, c)
      expect(type(c.events)).to.equal("table")
      expect(#c.events >= 1).to.equal(true)
    end)
  end)
```

- [ ] **Step 2: Run tests, verify they fail**

In Roblox Studio: Run mode → check Output for `[FAIL] fight events ...`. Three failures expected: events list is empty / nil because the engine doesn't write to it yet.

- [ ] **Step 3: Modify `CombatEngine.fight` to append events**

In `sync/ReplicatedStorage/shared/CombatEngine.luau`, edit the `fight` function. The current loop body around the slot-pick / damage / sink logic is at roughly lines 117–144. Replace the slot-handling block with:

```lua
  -- Initialise events list if caller did not pre-create it
  if not combat.events then combat.events = {} end

  local sunk = 0
  -- Fire each gun
  for _ = 1, state.guns do
    if combat.enemyTotal == 0 then break end
    -- Pick a random occupied slot (retry if empty)
    local attempts = 0
    local slot = nil
    repeat
      slot = math.random(1, 10)
      attempts = attempts + 1
    until combat.grid[slot] ~= nil or attempts > 50

    if combat.grid[slot] ~= nil then
      table.insert(combat.events, { type = "hit", slot = slot })
      local dmg = fnR(30) + 10  -- 10-39
      combat.grid[slot].damage = combat.grid[slot].damage + dmg
      if combat.grid[slot].damage > combat.grid[slot].maxHP then
        -- Ship sunk
        table.insert(combat.events, { type = "sink", slot = slot })
        combat.grid[slot] = nil
        combat.enemyTotal    = combat.enemyTotal    - 1
        combat.enemyOnScreen = combat.enemyOnScreen - 1
        sunk = sunk + 1
        -- Spawn replacement if waiting
        if combat.enemyWaiting > 0 and combat.enemyOnScreen == 0 then
          CombatEngine.spawnShips(combat, state.enemyBaseHP)
        end
      end
    end
  end
```

(Existing victory check, flee check, etc. below this block are unchanged for now — Tasks 2 and 3 add the spawn / flee event emissions.)

- [ ] **Step 4: Run tests, verify they pass**

Studio Run mode → expect three `[PASS]` lines for the `fight events` describe block.

- [ ] **Step 5: Commit**

```bash
git add sync/ReplicatedStorage/shared/CombatEngine.luau sync/ServerScriptService/Tests/CombatEngine.spec.luau
git commit -m "feat(combat): emit hit/sink events from CombatEngine.fight"
```

---

### Task 2: `CombatEngine.spawnShips` events for replacement appearances

**Files:**
- Modify: `sync/ReplicatedStorage/shared/CombatEngine.luau` (function `spawnShips`, ~lines 65–74)
- Test: `sync/ServerScriptService/Tests/CombatEngine.spec.luau` (extend the `fight events` describe)

- [ ] **Step 1: Write failing test for spawn events**

Append inside the `describe("fight events", ...)` block, before the closing `end)`:

```lua
    it("emits spawn events right after the sink that empties the screen", function()
      local s = makeState({ guns = 5, enemyBaseHP = 1 })
      local c = CombatEngine.initCombat(s, 4, 1)
      c.grid[1] = { maxHP = 1, damage = 0 }
      c.enemyOnScreen = 1
      c.enemyWaiting  = 3
      c.events = {}
      CombatEngine.fight(s, c)
      -- First two events: hit then sink at slot 1
      expect(c.events[1].type).to.equal("hit")
      expect(c.events[1].slot).to.equal(1)
      expect(c.events[2].type).to.equal("sink")
      expect(c.events[2].slot).to.equal(1)
      -- Next events should be spawns (3 of them, one per remaining waiting ship)
      local spawnCount = 0
      for i = 3, #c.events do
        if c.events[i].type == "spawn" then spawnCount = spawnCount + 1 end
        if c.events[i].type ~= "spawn" then break end
      end
      expect(spawnCount).to.equal(3)
    end)

    it("emits no spawn events when waiting=0", function()
      local s = makeState({ guns = 1, enemyBaseHP = 1 })
      local c = CombatEngine.initCombat(s, 1, 1)
      c.grid[2] = { maxHP = 1, damage = 0 }
      c.enemyOnScreen = 1
      c.enemyWaiting  = 0
      c.events = {}
      CombatEngine.fight(s, c)
      for _, e in ipairs(c.events) do
        expect(e.type ~= "spawn").to.equal(true)
      end
    end)
```

- [ ] **Step 2: Run tests, verify they fail**

Two new failures expected (spawn events missing).

- [ ] **Step 3: Modify `CombatEngine.spawnShips` to append spawn events**

Replace the existing function in `CombatEngine.luau` (~lines 65–74) with:

```lua
function CombatEngine.spawnShips(combat, enemyBaseHP)
  if not combat.events then combat.events = {} end
  for i = 1, 10 do
    if combat.enemyWaiting <= 0 then break end
    if combat.grid[i] == nil then
      combat.grid[i] = { maxHP = fnR(enemyBaseHP) + 20, damage = 0 }
      combat.enemyOnScreen = combat.enemyOnScreen + 1
      combat.enemyWaiting  = combat.enemyWaiting  - 1
      table.insert(combat.events, { type = "spawn", slot = i })
    end
  end
end
```

- [ ] **Step 4: Run tests, verify they pass**

- [ ] **Step 5: Commit**

```bash
git add sync/ReplicatedStorage/shared/CombatEngine.luau sync/ServerScriptService/Tests/CombatEngine.spec.luau
git commit -m "feat(combat): emit spawn events when replacements appear"
```

---

### Task 3: Post-fight enemy-flee pass emits flee events

**Files:**
- Modify: `sync/ReplicatedStorage/shared/CombatEngine.luau` (function `fight`, post-loop flee block ~lines 152–176)
- Test: `sync/ServerScriptService/Tests/CombatEngine.spec.luau` (extend `fight events` describe)

- [ ] **Step 1: Write failing test for post-fight flee events**

Append inside `describe("fight events", ...)`:

```lua
    it("emits flee events after the gun loop when enemies retreat", function()
      -- Setup: 4 ships on screen, no waiting; force the flee branch by setting
      -- runtime so attemptFlee path triggers. We can't easily seed RNG, so we
      -- run many trials and verify ordering when flee events do appear.
      local sawOrdering = false
      for trial = 1, 100 do
        local s = makeState({ guns = 1, enemyBaseHP = 10000 })
        local c = CombatEngine.initCombat(s, 4, 1)
        for i = 1, 4 do c.grid[i] = { maxHP = 10000, damage = 0 } end
        c.enemyOnScreen = 4
        c.enemyWaiting  = 0
        c.events = {}
        CombatEngine.fight(s, c)
        -- If any flee events appeared, all of them must come AFTER all hit/sink/spawn events
        local lastNonFleeIdx = 0
        local firstFleeIdx = nil
        for i, e in ipairs(c.events) do
          if e.type == "flee" then
            if firstFleeIdx == nil then firstFleeIdx = i end
          else
            if firstFleeIdx ~= nil then
              -- non-flee event after a flee event -> ordering violation
              error("non-flee event " .. e.type .. " appeared after flee event")
            end
            lastNonFleeIdx = i
          end
        end
        if firstFleeIdx ~= nil then
          sawOrdering = true
          break
        end
      end
      expect(sawOrdering).to.equal(true)
    end)
```

- [ ] **Step 2: Run tests, verify they fail**

Failure expected: flee events not yet emitted.

- [ ] **Step 3: Modify the post-loop flee block in `fight`**

In `CombatEngine.luau`, replace the post-loop flee block (currently ~lines 152–176):

```lua
  -- Enemy flee check: FN_R(S0) < SN * 0.6 / F1; skip if SN=0, SN=S0, SN<3
  local fleeCount = 0
  local sn = combat.enemyTotal
  local s0 = combat.originalCount
  local f1 = combat.encounterType
  if sn > 0 and sn ~= s0 and sn >= 3 then
    if fnR(s0) < sn * 0.6 / f1 then
      local w = fnR(sn / 3 / f1) + 1
      combat.enemyTotal   = combat.enemyTotal   - w
      -- Subtract from waiting pool first; remainder must come from on-screen
      local fromWaiting = math.min(w, combat.enemyWaiting)
      combat.enemyWaiting = combat.enemyWaiting - fromWaiting
      local fromScreen = w - fromWaiting
      local removed = 0
      for i = 10, 1, -1 do
        if removed >= fromScreen then break end
        if combat.grid[i] ~= nil then
          table.insert(combat.events, { type = "flee", slot = i })
          combat.grid[i] = nil
          combat.enemyOnScreen = math.max(0, combat.enemyOnScreen - 1)
          removed = removed + 1
        end
      end
      fleeCount = w
    end
  end
```

The `table.insert(combat.events, ...)` line is the new addition; everything else is unchanged.

- [ ] **Step 4: Run tests, verify they pass**

- [ ] **Step 5: Commit**

```bash
git add sync/ReplicatedStorage/shared/CombatEngine.luau sync/ServerScriptService/Tests/CombatEngine.spec.luau
git commit -m "feat(combat): emit flee events from post-fight enemy retreat"
```

---

### Task 4: `CombatEngine.partialEscape` emits flee events

**Files:**
- Modify: `sync/ReplicatedStorage/shared/CombatEngine.luau` (function `partialEscape`, ~lines 213–233)
- Test: `sync/ServerScriptService/Tests/CombatEngine.spec.luau` (new `describe("partialEscape events", ...)` block)

- [ ] **Step 1: Write failing test**

Add a new `describe` block right after the existing `describe("partialEscape", ...)`:

```lua
  describe("partialEscape events", function()
    it("appends one flee event per slot vacated", function()
      local fired = false
      for _ = 1, 200 do
        local s = makeState()
        local c = CombatEngine.initCombat(s, 10, 1)
        for i = 1, 10 do c.grid[i] = { maxHP = 50, damage = 0 } end
        c.enemyOnScreen = 10
        c.enemyWaiting  = 0
        c.events = {}
        local w = CombatEngine.partialEscape(c)
        if w > 0 then
          local fleeEvents = 0
          for _, e in ipairs(c.events) do
            if e.type == "flee" then fleeEvents = fleeEvents + 1 end
          end
          expect(fleeEvents).to.equal(w)
          fired = true
          break
        end
      end
      expect(fired).to.equal(true)
    end)
  end)
```

- [ ] **Step 2: Run test, verify it fails**

- [ ] **Step 3: Modify `partialEscape` to emit flee events**

In `CombatEngine.luau`, replace `partialEscape` with:

```lua
function CombatEngine.partialEscape(combat)
  if combat.enemyTotal <= 2 then return 0 end
  if math.random(0, 4) ~= 0 then return 0 end
  if not combat.events then combat.events = {} end

  local w = fnR(combat.enemyTotal / 2) + 1
  combat.enemyTotal   = combat.enemyTotal   - w
  -- Subtract from waiting pool first; remainder must come from on-screen
  local fromWaiting = math.min(w, combat.enemyWaiting)
  combat.enemyWaiting = combat.enemyWaiting - fromWaiting
  local fromScreen = w - fromWaiting
  local removed = 0
  for i = 10, 1, -1 do
    if removed >= fromScreen then break end
    if combat.grid[i] ~= nil then
      table.insert(combat.events, { type = "flee", slot = i })
      combat.grid[i] = nil
      combat.enemyOnScreen = math.max(0, combat.enemyOnScreen - 1)
      removed = removed + 1
    end
  end
  return w
end
```

- [ ] **Step 4: Run test, verify it passes**

- [ ] **Step 5: Commit**

```bash
git add sync/ReplicatedStorage/shared/CombatEngine.luau sync/ServerScriptService/Tests/CombatEngine.spec.luau
git commit -m "feat(combat): emit flee events from partialEscape"
```

---

### Task 5: `GameService` resets / clears `combat.events` per handler

**Files:**
- Modify: `sync/ServerScriptService/GameService.server.luau` (handlers `CombatFight`, `CombatRun`, `CombatThrow`, `CombatNoCommand`)

- [ ] **Step 1: Reset events at the top of `CombatFight` handler and clear after push**

In `GameService.server.luau`, locate the `CombatFight` handler (~line 677). Modify it as follows. The reset goes right after the early-return guards, and the clears go after each `pushState(player)`:

Find:
```lua
Remotes.CombatFight.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.combat or state.combat.outcome ~= nil then return end
  local combat = state.combat
  local pending = {}
```

Replace with:
```lua
Remotes.CombatFight.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.combat or state.combat.outcome ~= nil then return end
  local combat = state.combat
  combat.events = {}
  local pending = {}
```

Then for each occurrence of:
```lua
state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
```
within the `CombatFight` handler (there are 3), replace with:
```lua
state.pendingMessages = pending; pushState(player); state.pendingMessages = nil
if state.combat then state.combat.events = nil end
```

- [ ] **Step 2: Apply the same pattern to `CombatRun`, `CombatThrow`, `CombatNoCommand` handlers**

Same edits in each handler (~lines 750, 786, 798): add `combat.events = {}` after the existing guards, and append `if state.combat then state.combat.events = nil end` after each `pushState(player)` in those handlers.

- [ ] **Step 3: Verify with a quick smoke test in Studio Run mode**

The TestEZ tests still pass (no behaviour change in the engine). Confirm in Studio Output that `[PASS]` lines for `CombatEngine.spec` are unchanged.

- [ ] **Step 4: Commit**

```bash
git add sync/ServerScriptService/GameService.server.luau
git commit -m "feat(combat): plumb combat.events through GameService combat handlers"
```

---

## Phase 2 — Pure data submodule (`ShipSpriteData`)

### Task 6: Create `ShipSpriteData` module with base sprite + fragment tables

**Files:**
- Create: `sync/StarterGui/TaipanGui/GameController/Apple2/ShipSpriteData.luau`
- Create: `sync/ServerScriptService/Tests/ShipSpriteData.spec.luau`

- [ ] **Step 1: Add Azul mapping for the new ShipSpriteData module**

Edit `sourcemap.json`. Find the children list of the `GameController` script entry (where existing entries like `"Apple2"`, `"GameActions"`, etc. live as siblings of `Apple2Interface`). Inside the `"Apple2"` Folder's children, add a new `filePaths` entry mapping:

```json
{
  "name": "ShipSpriteData",
  "className": "ModuleScript",
  "filePaths": ["sync/StarterGui/TaipanGui/GameController/Apple2/ShipSpriteData.luau"]
}
```

The exact location: search for `"name": "PromptEngine"` inside the Apple2 folder children, and add the new entry as a sibling.

Also add a sibling entry for the spec under `ServerScriptService.Tests`:

Search for `"name": "CombatEngine.spec"` (or any existing `*.spec` entry under `Tests`) and add:

```json
{
  "name": "ShipSpriteData.spec",
  "className": "ModuleScript",
  "filePaths": ["sync/ServerScriptService/Tests/ShipSpriteData.spec.luau"]
}
```

- [ ] **Step 2: Write the failing test file**

Create `sync/ServerScriptService/Tests/ShipSpriteData.spec.luau`:

```lua
-- ShipSpriteData.spec.lua
-- Tests for the pure ship-sprite data module.

return function()
  local ShipSpriteData = require(game:GetService("StarterGui").TaipanGui.GameController.Apple2.ShipSpriteData)

  describe("baseSprite", function()
    it("is a 5-row table of 7-char strings", function()
      local rows = ShipSpriteData.baseSprite
      expect(#rows).to.equal(5)
      for i = 1, 5 do
        expect(#rows[i]).to.equal(7)
      end
    end)

    it("matches the BASIC string ABCDEFG / HIJKLMN / OIJKLPQ / RSTUVWX / YJJJJJZ", function()
      local rows = ShipSpriteData.baseSprite
      expect(rows[1]).to.equal("ABCDEFG")
      expect(rows[2]).to.equal("HIJKLMN")
      expect(rows[3]).to.equal("OIJKLPQ")
      expect(rows[4]).to.equal("RSTUVWX")
      expect(rows[5]).to.equal("YJJJJJZ")
    end)
  end)

  describe("damageFragments", function()
    it("has 6 entries, each with two zones (J=0 upper, J=1 lower)", function()
      expect(#ShipSpriteData.damageFragments).to.equal(6)
      for i = 1, 6 do
        local entry = ShipSpriteData.damageFragments[i]
        expect(entry[0]).to.be.ok()
        expect(entry[1]).to.be.ok()
        expect(type(entry[0].chars)).to.equal("table")
        expect(type(entry[1].chars)).to.equal("table")
        expect(type(entry[0].dx)).to.equal("number")
        expect(type(entry[0].dy)).to.equal("number")
      end
    end)

    it("upper-zone (J=0) Y offsets are all 0..2", function()
      for i = 1, 6 do
        local f = ShipSpriteData.damageFragments[i][0]
        expect(f.dy >= 0 and f.dy <= 2).to.equal(true)
      end
    end)

    it("lower-zone (J=1) Y offsets are all 3..4", function()
      for i = 1, 6 do
        local f = ShipSpriteData.damageFragments[i][1]
        expect(f.dy >= 3 and f.dy <= 4).to.equal(true)
      end
    end)

    it("multi-row fragment (idx 2 J=0) is 'fg' then 'mn' on consecutive rows", function()
      local f = ShipSpriteData.damageFragments[2][0]
      expect(#f.chars).to.equal(2)
      expect(f.chars[1]).to.equal("fg")
      expect(f.chars[2]).to.equal("mn")
    end)

    it("multi-row fragment (idx 4 J=1) is 'x' then 'z' on consecutive rows", function()
      local f = ShipSpriteData.damageFragments[4][1]
      expect(#f.chars).to.equal(2)
      expect(f.chars[1]).to.equal("x")
      expect(f.chars[2]).to.equal("z")
    end)
  end)

  describe("applyDamageFragment", function()
    it("overwrites the correct cells of a 5x7 grid", function()
      local grid = ShipSpriteData.newDamageGrid()
      ShipSpriteData.applyDamageFragment(grid, 1, 0)  -- "cde" at X+2, Y+0
      expect(grid[1][3]).to.equal("c")
      expect(grid[1][4]).to.equal("d")
      expect(grid[1][5]).to.equal("e")
    end)

    it("handles multi-row fragments (idx 2 J=0): 'fg' on row 1, 'mn' on row 2 at X+5", function()
      local grid = ShipSpriteData.newDamageGrid()
      ShipSpriteData.applyDamageFragment(grid, 2, 0)
      expect(grid[1][6]).to.equal("f")
      expect(grid[1][7]).to.equal("g")
      expect(grid[2][6]).to.equal("m")
      expect(grid[2][7]).to.equal("n")
    end)
  end)

  describe("renderRows", function()
    it("returns base sprite when grid is empty", function()
      local grid = ShipSpriteData.newDamageGrid()
      local rows = ShipSpriteData.renderRows(grid)
      expect(rows[1]).to.equal("ABCDEFG")
      expect(rows[5]).to.equal("YJJJJJZ")
    end)

    it("overlays damage chars on the base sprite", function()
      local grid = ShipSpriteData.newDamageGrid()
      ShipSpriteData.applyDamageFragment(grid, 1, 0)  -- "cde" at row 1 col 3..5
      local rows = ShipSpriteData.renderRows(grid)
      expect(rows[1]:sub(3, 5)).to.equal("cde")
      expect(rows[1]:sub(1, 2)).to.equal("AB")  -- untouched
      expect(rows[1]:sub(6, 7)).to.equal("FG")  -- untouched
    end)
  end)
end
```

- [ ] **Step 3: Run the test, verify it fails**

Studio Run mode → expect failures: `ShipSpriteData was not found` (module doesn't exist).

- [ ] **Step 4: Create the `ShipSpriteData` module**

Create `sync/StarterGui/TaipanGui/GameController/Apple2/ShipSpriteData.luau`:

```lua
-- ShipSpriteData.lua
-- Pure data module for combat ship sprites and damage fragments.
-- Mirrors BASIC variables SH$ (line 10250) and DM$/DL% (lines 10270-10300)
-- from references/taipan-applesoft-annotated.txt.

local ShipSpriteData = {}

-- Base 5-row x 7-col ship sprite (from BASIC SH$).
ShipSpriteData.baseSprite = {
  "ABCDEFG",
  "HIJKLMN",
  "OIJKLPQ",
  "RSTUVWX",
  "YJJJJJZ",
}

-- Damage fragments. Indexed [1..6][0..1].
-- chars: array of strings (length 1 = single-row fragment, length 2 = two-row fragment).
-- dx, dy: offset in 0-based char coords from the slot's top-left.
-- Source: BASIC line 10300:
--   DATA cde,20, r,3, fg*,mn,50, tu,23, ij,11, vw,43, 0,22, x*,z,63, kl,32, 12,14, pq,52, 345,34
-- (Decoded as 6 fragment-pairs; the offset is encoded as 2 digits "tens=dx, units=dy".)
local function frag(chars, code)
  local dx = math.floor(code / 10)
  local dy = code - dx * 10
  return { chars = chars, dx = dx, dy = dy }
end

ShipSpriteData.damageFragments = {
  [1] = { [0] = frag({ "cde" },     20), [1] = frag({ "r" },        3) },
  [2] = { [0] = frag({ "fg", "mn" }, 50), [1] = frag({ "tu" },      23) },
  [3] = { [0] = frag({ "ij" },      11), [1] = frag({ "vw" },      43) },
  [4] = { [0] = frag({ "0" },       22), [1] = frag({ "x", "z" },  63) },
  [5] = { [0] = frag({ "kl" },      32), [1] = frag({ "12" },      14) },
  [6] = { [0] = frag({ "pq" },      52), [1] = frag({ "345" },     34) },
}

-- newDamageGrid: returns a 5-row sparse map; grid[row][col] = override char, or nil.
function ShipSpriteData.newDamageGrid()
  local g = {}
  for r = 1, 5 do g[r] = {} end
  return g
end

-- applyDamageFragment: mutate grid by writing the chars of fragment[idx][zone] at its (dx, dy).
-- Rows / cols are 1-based; dx / dy are 0-based offsets.
function ShipSpriteData.applyDamageFragment(grid, idx, zone)
  local f = ShipSpriteData.damageFragments[idx][zone]
  for rowOffset, segment in ipairs(f.chars) do
    local rowIdx = f.dy + rowOffset
    if rowIdx >= 1 and rowIdx <= 5 then
      for c = 1, #segment do
        local colIdx = f.dx + c
        if colIdx >= 1 and colIdx <= 7 then
          grid[rowIdx][colIdx] = segment:sub(c, c)
        end
      end
    end
  end
end

-- renderRows: produce 5 strings of length 7, with damage cells overlaid on the base sprite.
function ShipSpriteData.renderRows(grid)
  local rows = {}
  for r = 1, 5 do
    local base = ShipSpriteData.baseSprite[r]
    local out = {}
    for c = 1, 7 do
      out[c] = grid[r][c] or base:sub(c, c)
    end
    rows[r] = table.concat(out)
  end
  return rows
end

return ShipSpriteData
```

- [ ] **Step 5: Run test, verify all pass**

- [ ] **Step 6: Commit**

```bash
git add sourcemap.json sync/StarterGui/TaipanGui/GameController/Apple2/ShipSpriteData.luau sync/ServerScriptService/Tests/ShipSpriteData.spec.luau
git commit -m "feat(apple2): add ShipSpriteData pure module with base sprite and damage fragments"
```

---

## Phase 3 — `ShipGrid` GUI module

### Task 7: Create `ShipGrid` skeleton with slot frames and glyph rendering primitive

**Files:**
- Create: `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau`
- Modify: `sourcemap.json` (add ShipGrid mapping under Apple2)

Note: This module is verified by MCP playtest, not unit tests (it touches Roblox UI primitives). Each subsequent task adds a method and exercises it via a small inline diagnostic script you can paste into Studio's Run-mode command bar.

- [ ] **Step 1: Add Azul mapping**

Edit `sourcemap.json`. Add inside the `Apple2` folder's children, alongside `ShipSpriteData`:

```json
{
  "name": "ShipGrid",
  "className": "ModuleScript",
  "filePaths": ["sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau"]
}
```

- [ ] **Step 2: Create the `ShipGrid` module skeleton**

Create `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau`:

```lua
-- ShipGrid.lua
-- 10-slot enemy-ship sprite layer for the Apple II combat scene.
-- Sibling to Terminal and GlitchLayer; uses TaipanThickFont glyphs as ImageLabels.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Text              = require(ReplicatedStorage.Text)
local ShipSpriteData    = require(script.Parent.ShipSpriteData)

-- Coordinate constants must match Terminal.luau exactly so sprites land in the right cells.
local TEXT_SIZE     = 3
local CHAR_WIDTH    = 14 * TEXT_SIZE   -- 42 virtual px
local ROW_HEIGHT    = 16 * TEXT_SIZE   -- 48 virtual px
local X_OFFSET      = 30               -- left margin (matches Terminal)
local SCREEN_W      = 1920
local SCREEN_H      = 1080

local SHIP_W_CHARS  = 7
local SHIP_H_ROWS   = 5
local SLOT_W_PX     = SHIP_W_CHARS * CHAR_WIDTH
local SLOT_H_PX     = SHIP_H_ROWS * ROW_HEIGHT

local THICK_FONT_NAME = "TaipanThickFont"

local ShipGrid = {}

-- BASIC slot-coordinate formula: X = (i mod 5) * 8 + 1 (1-based char col), Y = floor(i/5) * 6 + 7 (1-based row).
-- Returns top-left pixel coordinates of slot index 1..10.
local function slotPixelTopLeft(slotIndex)
  local i = slotIndex - 1                          -- back to 0-based for the formula
  local charCol = (i % 5) * 8 + 1                  -- 1, 9, 17, 25, 33
  local rowIdx  = math.floor(i / 5) * 6 + 7        -- 7 or 13
  local x = X_OFFSET + (charCol - 1) * CHAR_WIDTH
  local y = (rowIdx - 1) * ROW_HEIGHT
  return x, y
end

-- Lazily resolve the TaipanThickFont folder + atlas asset once.
local function getThickFont()
  local fontFolder = ReplicatedStorage.Text.Fonts:FindFirstChild(THICK_FONT_NAME)
  assert(fontFolder, "TaipanThickFont not found in ReplicatedStorage.Text.Fonts")
  local fontData = require(fontFolder.FontData)
  local imageId  = fontFolder.ImageID.Value
  return fontData, imageId
end

function ShipGrid.new(displayOrder)
  local gui = Text.GetTextGUI(displayOrder or 6)   -- > Terminal's 5 so sprites overlay
  gui.Name   = "TaipanShipGrid"
  gui.Parent = Players.LocalPlayer.PlayerGui

  local fontData, imageId = getThickFont()

  -- Per-slot state. slotState[i] = { frame, container, glyphs, damageGrid, animating, sinkTween }
  local slotState = {}

  -- Helper: build a fresh ImageLabel for one glyph, parented to a Frame, at relative pixel pos.
  local function makeGlyph(parent, codepoint, relX, relY)
    local frame = fontData[codepoint]
    if not frame then
      -- Missing glyph; return a blank label so we don't crash on unexpected chars.
      local blank = Instance.new("Frame")
      blank.BackgroundTransparency = 1
      blank.Size = UDim2.fromScale(CHAR_WIDTH / SCREEN_W, ROW_HEIGHT / SCREEN_H)
      blank.Position = UDim2.fromScale(relX / SCREEN_W, relY / SCREEN_H)
      blank.Parent = parent
      return blank
    end
    local img = Instance.new("ImageLabel")
    img.BackgroundTransparency = 1
    img.Image = imageId
    img.ImageRectOffset = Vector2.new(frame.x, frame.y)
    img.ImageRectSize   = Vector2.new(frame.width, frame.height)
    img.Size            = UDim2.fromScale(
      (frame.width  * TEXT_SIZE) / SCREEN_W,
      (frame.height * TEXT_SIZE) / SCREEN_H)
    img.Position        = UDim2.fromScale(relX / SCREEN_W, relY / SCREEN_H)
    img.ImageColor3     = Color3.fromRGB(140, 200, 80)  -- terminal green
    img.Parent          = parent
    return img
  end

  -- Build (or rebuild) the 35 glyph ImageLabels for a slot from a damage-overlaid render.
  local function paintSlot(slot, rows)
    local st = slotState[slot]
    -- Clear existing glyphs
    if st.glyphs then
      for _, g in ipairs(st.glyphs) do g:Destroy() end
    end
    st.glyphs = {}
    for r = 1, SHIP_H_ROWS do
      local rowText = rows[r]
      for c = 1, SHIP_W_CHARS do
        local ch = rowText:sub(c, c)
        local cp = string.byte(ch)
        local relX = (c - 1) * CHAR_WIDTH
        local relY = (r - 1) * ROW_HEIGHT
        local g = makeGlyph(st.container, cp, relX, relY)
        table.insert(st.glyphs, g)
      end
    end
  end

  -- Build the per-slot Frame + container hierarchy.
  for slot = 1, 10 do
    local x, y = slotPixelTopLeft(slot)
    local frame = Instance.new("Frame")
    frame.Name = "Slot" .. slot
    frame.BackgroundTransparency = 1
    frame.Size     = UDim2.fromScale(SLOT_W_PX / SCREEN_W, SLOT_H_PX / SCREEN_H)
    frame.Position = UDim2.fromScale(x / SCREEN_W, y / SCREEN_H)
    frame.ClipsDescendants = true
    frame.Visible = false   -- slots start empty
    frame.Parent  = gui.TextParent

    local container = Instance.new("Frame")
    container.Name = "SpriteContainer"
    container.BackgroundTransparency = 1
    container.Size     = UDim2.fromScale(1, 1)
    container.Position = UDim2.fromScale(0, 0)
    container.Parent   = frame

    slotState[slot] = {
      frame      = frame,
      container  = container,
      glyphs     = nil,
      damageGrid = nil,
      animating  = false,
      sinkTween  = nil,
    }
  end

  local grid = {}
  grid._gui       = gui
  grid._slotState = slotState
  grid._paintSlot = paintSlot

  function grid.destroy()
    gui:Destroy()
  end

  return grid
end

return ShipGrid
```

- [ ] **Step 3: Smoke-test in Studio**

In Studio Run mode, paste in the command bar:

```lua
local sg = require(game.StarterGui.TaipanGui.GameController.Apple2.ShipGrid).new(6)
print("ShipGrid created:", sg._gui)
```

Expected: a print line shows the ScreenGui instance; no errors.

- [ ] **Step 4: Commit**

```bash
git add sourcemap.json sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau
git commit -m "feat(apple2): add ShipGrid skeleton with slot frames and glyph primitive"
```

---

### Task 8: `ShipGrid.draw` — render full ship sprite at a slot

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau`

- [ ] **Step 1: Add the `draw` method**

In `ShipGrid.luau`, just before `return grid`, add:

```lua
  function grid.draw(slot)
    local st = slotState[slot]
    if not st then return end
    st.damageGrid = ShipSpriteData.newDamageGrid()
    st.container.Position = UDim2.fromScale(0, 0)  -- reset any prior sink offset
    paintSlot(slot, ShipSpriteData.renderRows(st.damageGrid))
    st.frame.Visible = true
    st.animating = false
  end
```

- [ ] **Step 2: Smoke-test in Studio**

In Studio Run mode (with the game running so PlayerGui exists), paste:

```lua
local sg = require(game.StarterGui.TaipanGui.GameController.Apple2.ShipGrid).new(6)
sg.draw(1)
sg.draw(5)
sg.draw(6)
sg.draw(10)
```

Expected: four ship sprites visible in slots 1, 5, 6, 10. Slots 1+5 on the upper row (slots 1..5 = upper); slots 6+10 on the lower row.

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau
git commit -m "feat(apple2): ShipGrid.draw renders fresh ship at slot"
```

---

### Task 9: `ShipGrid.flee` — instant blank

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau`

- [ ] **Step 1: Add the `flee` method**

Just below `grid.draw`, add:

```lua
  function grid.flee(slot)
    local st = slotState[slot]
    if not st then return end
    st.frame.Visible = false
    st.damageGrid = nil
    if st.glyphs then
      for _, g in ipairs(st.glyphs) do g:Destroy() end
      st.glyphs = nil
    end
    if st.sinkTween then st.sinkTween:Cancel(); st.sinkTween = nil end
    st.animating = false
  end
```

- [ ] **Step 2: Smoke-test in Studio**

```lua
local sg = require(game.StarterGui.TaipanGui.GameController.Apple2.ShipGrid).new(6)
sg.draw(3)
task.wait(1)
sg.flee(3)
```

Expected: ship appears at slot 3, vanishes after 1 second.

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau
git commit -m "feat(apple2): ShipGrid.flee blanks slot instantly"
```

---

### Task 10: `ShipGrid.applyHit` — overlay damage fragments + hit-flash

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau`

- [ ] **Step 1: Add the `applyHit` method**

Below `grid.flee`, add:

```lua
  -- Hit-flash duration (ms). Tunable.
  local HIT_FLASH_S = 0.08

  function grid.applyHit(slot, onComplete)
    local st = slotState[slot]
    if not st or not st.damageGrid then
      if onComplete then onComplete() end
      return
    end

    -- Pick two random fragments (one per zone, 0=upper, 1=lower).
    local idx0 = math.random(1, 6)
    local idx1 = math.random(1, 6)
    ShipSpriteData.applyDamageFragment(st.damageGrid, idx0, 0)
    ShipSpriteData.applyDamageFragment(st.damageGrid, idx1, 1)
    paintSlot(slot, ShipSpriteData.renderRows(st.damageGrid))

    -- Hit-flash: invert glyph colours briefly by toggling ImageColor3.
    local FLASH_COLOR = Color3.fromRGB(255, 255, 255)
    local NORMAL_COLOR = Color3.fromRGB(140, 200, 80)
    for _, g in ipairs(st.glyphs) do
      if g:IsA("ImageLabel") then g.ImageColor3 = FLASH_COLOR end
    end
    task.delay(HIT_FLASH_S, function()
      for _, g in ipairs(st.glyphs) do
        if g:IsA("ImageLabel") then g.ImageColor3 = NORMAL_COLOR end
      end
      if onComplete then onComplete() end
    end)
  end
```

- [ ] **Step 2: Smoke-test in Studio**

```lua
local sg = require(game.StarterGui.TaipanGui.GameController.Apple2.ShipGrid).new(6)
sg.draw(2)
for i = 1, 5 do
  task.wait(0.5)
  sg.applyHit(2)
end
```

Expected: ship at slot 2 flashes white briefly with each hit and accumulates damage characters across the 5 hits.

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau
git commit -m "feat(apple2): ShipGrid.applyHit with damage overlay and hit-flash"
```

---

### Task 11: `ShipGrid.sink` — tween container Y, clip, blank on complete

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau`

- [ ] **Step 1: Add the `sink` method**

Below `grid.applyHit`, add:

```lua
  -- Sink animation duration range (seconds). Random per ship; matches BASIC's R(R(192)) seed.
  local SINK_MIN_S = 0.4
  local SINK_MAX_S = 1.6

  function grid.sink(slot, onComplete)
    local st = slotState[slot]
    if not st or st.animating then
      if onComplete then onComplete() end
      return
    end
    st.animating = true

    local duration = SINK_MIN_S + math.random() * (SINK_MAX_S - SINK_MIN_S)
    local goal = { Position = UDim2.fromScale(0, SLOT_H_PX / SCREEN_H) }
    local info = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    local tween = TweenService:Create(st.container, info, goal)
    st.sinkTween = tween
    tween.Completed:Connect(function()
      st.frame.Visible = false
      if st.glyphs then
        for _, g in ipairs(st.glyphs) do g:Destroy() end
        st.glyphs = nil
      end
      st.damageGrid = nil
      st.animating = false
      st.sinkTween = nil
      if onComplete then onComplete() end
    end)
    tween:Play()
  end
```

- [ ] **Step 2: Smoke-test in Studio**

```lua
local sg = require(game.StarterGui.TaipanGui.GameController.Apple2.ShipGrid).new(6)
sg.draw(4)
task.wait(0.5)
sg.sink(4, function() print("Slot 4 sunk!") end)
```

Expected: ship at slot 4 slides down and the bottom rows clip at the slot edge as it descends. Console prints `Slot 4 sunk!` when complete. Try a few times to see the random-speed variation.

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau
git commit -m "feat(apple2): ShipGrid.sink with random-speed clipped tween"
```

---

### Task 12: `ShipGrid.spawn` and `ShipGrid.clearAll` + `show` / `hide`

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau`

- [ ] **Step 1: Add the remaining methods**

Below `grid.sink`, add:

```lua
  -- spawn is currently identical to draw; left as a separate API so a future
  -- "appear-in" flash can be added without touching call sites.
  function grid.spawn(slot)
    grid.draw(slot)
  end

  function grid.clearAll()
    for slot = 1, 10 do
      grid.flee(slot)
    end
  end

  function grid.show()
    grid._gui.Enabled = true
  end

  function grid.hide()
    grid._gui.Enabled = false
  end

  -- isAnimating: true if any slot is currently sinking (used by Apple2Interface to gate prompts).
  function grid.isAnimating()
    for slot = 1, 10 do
      if slotState[slot].animating then return true end
    end
    return false
  end
```

- [ ] **Step 2: Smoke-test in Studio**

```lua
local sg = require(game.StarterGui.TaipanGui.GameController.Apple2.ShipGrid).new(6)
for i = 1, 10 do sg.spawn(i) end
task.wait(0.5)
sg.hide()
task.wait(0.5)
sg.show()
task.wait(0.5)
sg.clearAll()
```

Expected: 10 ships appear; vanish; reappear; vanish.

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/ShipGrid.luau
git commit -m "feat(apple2): ShipGrid.spawn/clearAll/show/hide/isAnimating"
```

---

## Phase 4 — `Apple2Interface` integration

### Task 13: Instantiate `ShipGrid` and add it to the destroy path

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau`

- [ ] **Step 1: Require and instantiate `ShipGrid`**

In `Apple2Interface.luau`, locate the `Apple2Interface.new` function near the existing `local term = Terminal.new(5)` line (~line 49). Add:

Find:
```lua
local Terminal     = require(script.Parent.Apple2.Terminal)
local GlitchLayer  = require(script.Parent.Apple2.GlitchLayer)
local KeyInput     = require(script.Parent.Apple2.KeyInput)
local PromptEngine = require(script.Parent.Apple2.PromptEngine)
local SoundPlayer  = require(ReplicatedStorage.SoundPlayer)
```

Replace with:
```lua
local Terminal     = require(script.Parent.Apple2.Terminal)
local GlitchLayer  = require(script.Parent.Apple2.GlitchLayer)
local KeyInput     = require(script.Parent.Apple2.KeyInput)
local PromptEngine = require(script.Parent.Apple2.PromptEngine)
local ShipGrid     = require(script.Parent.Apple2.ShipGrid)
local SoundPlayer  = require(ReplicatedStorage.SoundPlayer)
```

Find:
```lua
function Apple2Interface.new(screenGui, actions)
  local term    = Terminal.new(5)  -- displayOrder 5
  local glitch  = GlitchLayer.new(term._gui)
  local ki      = KeyInput.new(screenGui)
```

Replace with:
```lua
function Apple2Interface.new(screenGui, actions)
  local term    = Terminal.new(5)  -- displayOrder 5
  local shipGrid = ShipGrid.new(6)  -- displayOrder 6 (above terminal)
  shipGrid.hide()                   -- start hidden; combat scene will show it
  local glitch  = GlitchLayer.new(term._gui)
  local ki      = KeyInput.new(screenGui)
```

Find the existing `adapter.destroy`:
```lua
  function adapter.destroy()
    ki.destroy()
    term.destroy()
    glitch.destroy()
  end
```

Replace with:
```lua
  function adapter.destroy()
    ki.destroy()
    term.destroy()
    glitch.destroy()
    shipGrid.destroy()
  end
```

- [ ] **Step 2: Smoke-test**

Open Studio, enter Play mode, switch to the Apple II interface (start a new game with the F/G keypress flow). Verify the game still works and no errors appear in Output. ShipGrid is hidden, so nothing should look different yet.

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau
git commit -m "feat(apple2): wire ShipGrid layer into Apple2Interface lifecycle"
```

---

### Task 14: Show / hide `ShipGrid` on combat enter / exit

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` (function `adapter.update`, ~line 250)

- [ ] **Step 1: Track combat-active transitions and show/hide**

In `Apple2Interface.luau`, locate the `adapter.update` function (~line 250). Find the block:

```lua
  function adapter.update(state)
    lastState = state

    if state.combat == nil then
      queuedCommand = nil
      roundPhase = nil
      roundGen += 1  -- invalidate any in-flight phase callbacks
    end
```

Replace with:

```lua
  function adapter.update(state)
    local prevCombat = lastState and lastState.combat ~= nil
    local nextCombat = state.combat ~= nil
    lastState = state

    if not nextCombat then
      queuedCommand = nil
      roundPhase = nil
      roundGen += 1  -- invalidate any in-flight phase callbacks
    end

    -- Combat boundary transitions
    if nextCombat and not prevCombat then
      shipGrid.clearAll()   -- start fresh
      shipGrid.show()
      -- Initial draw of ships currently on screen
      if type(state.combat.grid) == "table" then
        for slot = 1, 10 do
          if state.combat.grid[slot] ~= nil then
            shipGrid.draw(slot)
          end
        end
      end
    elseif prevCombat and not nextCombat then
      shipGrid.clearAll()
      shipGrid.hide()
    end
```

- [ ] **Step 2: Smoke-test**

In Play mode, trigger a combat encounter (travel until pirates attack). Verify ships render in their slots when combat starts. End the combat (run away or fight victory). Verify the layer disappears.

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau
git commit -m "feat(apple2): show/hide ShipGrid on combat enter/exit with initial draw"
```

---

### Task 15: Animator queue drains `combat.events` sequentially

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau`

- [ ] **Step 1: Add the animator state and drain function**

In `Apple2Interface.luau`, just below the existing `local notifQueue = {}` line (~line 70), add:

```lua
  local combatAnimQueue = {}
  local combatAnimDraining = false
```

Then, just above the `local function isServerDriven(state)` line (~line 75), add the drain function:

```lua
  local function drainCombatEvents()
    if combatAnimDraining then return end
    combatAnimDraining = true
    task.spawn(function()
      while #combatAnimQueue > 0 do
        local evt = table.remove(combatAnimQueue, 1)
        local done = false
        local function onComplete() done = true end

        if evt.type == "hit" then
          shipGrid.applyHit(evt.slot, onComplete)
        elseif evt.type == "sink" then
          shipGrid.sink(evt.slot, onComplete)
        elseif evt.type == "spawn" then
          shipGrid.spawn(evt.slot)
          done = true
        elseif evt.type == "flee" then
          shipGrid.flee(evt.slot)
          done = true
        else
          done = true
        end

        while not done do task.wait(0.02) end
        task.wait(0.05)  -- 50 ms inter-event gap
      end
      combatAnimDraining = false
      -- After drain, attempt to start the next round (will no-op if any other guard fails).
      startRoundIfCombat()
    end)
  end
```

- [ ] **Step 2: Enqueue events on every combat StateUpdate**

In `adapter.update`, find the existing block that handles `state.pendingMessages` (~line 260):

```lua
    -- Drain any pendingMessages from the state update into the queue
    if type(state.pendingMessages) == "table" then
      for _, entry in ipairs(state.pendingMessages) do
        table.insert(notifQueue, entry)
      end
    end
```

Just below that, before the `if isServerDriven(state) then` block, add:

```lua
    -- Drain any combat.events into the animator queue
    if nextCombat and type(state.combat.events) == "table" then
      for _, evt in ipairs(state.combat.events) do
        table.insert(combatAnimQueue, evt)
      end
      drainCombatEvents()
    end
```

- [ ] **Step 3: Gate `startRoundIfCombat` on the animator**

Find the existing `startRoundIfCombat` function (~line 204):

```lua
  startRoundIfCombat = function()
    if not (lastState and lastState.combat) then return end
    if roundPhase ~= nil then return end
    if #notifQueue > 0 then return end
    roundGen += 1
```

Replace with:

```lua
  startRoundIfCombat = function()
    if not (lastState and lastState.combat) then return end
    if roundPhase ~= nil then return end
    if #notifQueue > 0 then return end
    if combatAnimDraining or #combatAnimQueue > 0 then return end
    roundGen += 1
```

- [ ] **Step 4: Smoke-test**

In Play mode, trigger a combat. Press F to fight. Watch:
- Ships render in their slots ✓
- On gun fire: hit-flash + damage chars accumulate ✓
- On sinking: ship slides down with bottom clipped ✓
- On respawn: new ship appears ✓
- F/R/T prompt is hidden during animations and reappears once they finish ✓

- [ ] **Step 5: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau
git commit -m "feat(apple2): combat animator drains events into ShipGrid sequentially"
```

---

## Phase 5 — Cleanup

### Task 16: Remove the placeholder Ships row from `PromptEngine.sceneCombatLayout`

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (function `sceneCombatLayout`, ~lines 605–697)

- [ ] **Step 1: Remove the row5 placeholder and its function**

In `PromptEngine.luau`, locate `sceneCombatLayout` (~line 605). Find the `row5` definition and its insertion:

```lua
  local function row5()
    return { text = "  Ships: [" .. gridStr .. "]", color = GREEN }
  end
```

And:

```lua
  rows[1] = row1()
  rows[2] = row2()
  rows[3] = row3()
  rows[4] = row4()
  rows[5] = row5()
  for r = 6, 24 do rows[r] = { text = "", color = AMBER } end
```

Replace the rows-assignment block with:

```lua
  rows[1] = row1()
  rows[2] = row2()
  rows[3] = row3()
  rows[4] = row4()
  -- row 5 intentionally blank: ShipGrid layer renders the actual sprites in rows 7-17
  for r = 5, 24 do rows[r] = { text = "", color = AMBER } end
```

Then delete the now-unused `row5` function above.

Also remove the now-unused `gridStr` building block (~lines 616-620):

```lua
  -- 10-slot ship grid: # = alive, . = empty
  local gridStr = ""
  for i = 1, 10 do
    gridStr = gridStr .. (grid[i] ~= nil and "#" or ".")
  end
```

Delete this block. The `grid` local declared at the top of the function is still used? Check — if not, remove `local grid = combat.grid or {}` too. Search the function body to confirm no other use, then prune.

- [ ] **Step 2: Smoke-test**

Restart Play mode, trigger combat. Verify:
- Row 5 is blank (no `Ships: [...]` text) ✓
- Sprite grid is visible at rows 7-17 (rendered by ShipGrid layer) ✓

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "refactor(apple2): drop placeholder ship grid string from combat scene"
```

---

## Phase 6 — Verification

### Task 17: MCP playtest checklist

**Files:** none (manual verification)

Run through the complete checklist in Roblox Studio Play mode using MCP tools. For each check below, capture a screenshot via `screen_capture` if a visual is hard to verify by eye.

- [ ] **Combat enters cleanly:** Travel until pirates encounter you. Sprites render at the correct slot coordinates (5 slots top row at display rows 7-11, 5 slots bottom row at display rows 13-17). Compare slot positions against `slotPixelTopLeft(i)` for i = 1..10.

- [ ] **Single-shot hit (survives):** With low gun count (1) vs high-HP enemy (use a high enemyBaseHP encounter), press F. Hit-flash plays, damage fragment characters appear on the sprite, and the sprite stays visible. Press F a few more times — fragments accumulate.

- [ ] **Killing shot:** Force a sink (multiple hits or low enemyBaseHP). Hit-flash plays on the killing shot, then the ship slides downward inside its slot. The bottom of the sprite clips at the slot edge as it descends. Slot ends blank.

- [ ] **Random sink speed:** Repeat the kill several times. Each sink should visibly take a different duration in the 0.4–1.6 s range.

- [ ] **Spawn after wipe:** With a fight that triggers replacement spawning (waiting > 0, kill all on-screen), the new ships appear at fresh slots after the triggering sink. Surplus guns in the same round may then fire on the new ships, with their `hit` events queued after the `spawn` events.

- [ ] **Successful run:** Press R until you escape. All slots blank instantly. ShipGrid layer hides.

- [ ] **Failed run with partial escape:** When the run fails and partial escape triggers, the slots that vacated blank instantly while the rest stay.

- [ ] **Input gating:** Verify the `(F)ight (R)un (T)hrow` prompt is hidden while the animation queue is draining and reappears when it finishes.

- [ ] **Combat exit:** Win the fight (sink them all). ShipGrid layer hides; the combat scene transitions out as before.

- [ ] **Reconnect resync:** While in combat, run `Remotes.RequestStateUpdate:FireServer()` from `execute_luau` and verify the snapshot redraws ships without animation and without preserved damage chars (matches BASIC).

If any check fails, file an issue with the failing scenario and re-open the relevant phase task.

- [ ] **Commit (if any tweaks were made during playtest)**

```bash
git add -A
git commit -m "fix(apple2): combat sprite playtest tweaks"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Tasks |
|---|---|
| §Requirements 1: Draw fresh ship at any slot | 8 (`draw`), 14 (initial draw on combat enter) |
| §Requirements 2: Damage overlay + hit-flash on gun hit | 6 (data), 10 (`applyHit`) |
| §Requirements 3: Instant blank on flee | 9 (`flee`), 4 (events from partialEscape), 3 (events from post-fight enemy flee) |
| §Requirements 4: Random-speed sink with bottom clipping | 11 (`sink` with TweenService + `ClipsDescendants`) |
| §Requirements 5: Replace placeholder Ships row | 16 |
| §Requirements 6: Block input during animations | 15 (`startRoundIfCombat` gate) |
| §CombatEngine event timeline (hit/sink/spawn/flee) | 1, 2, 3, 4 |
| §State plumbing for `state.combat.events` | 5 |
| §ShipGrid module API and per-slot state | 7, 8, 9, 10, 11, 12 |
| §Animator + initial render + resync + combat exit | 13, 14, 15 |
| §Tests | 1, 2, 3, 4 (CombatEngine.spec), 6 (ShipSpriteData.spec), 17 (MCP playtest) |

All spec requirements have at least one task. No gaps.

**Placeholder scan:** No "TBD", "TODO", or vague placeholders. All steps contain concrete code or commands. Test code is shown in full. The "Open questions" from the spec (font codepoint mapping, easing curve, spawn appear-in flash) are documented as defaults in Tasks 7 / 11 / 12 with explicit tunable points; they do not block implementation.

**Type / signature consistency:** `ShipGrid.draw(slot)`, `ShipGrid.flee(slot)`, `ShipGrid.applyHit(slot, onComplete)`, `ShipGrid.sink(slot, onComplete)`, `ShipGrid.spawn(slot)`, `ShipGrid.clearAll()`, `ShipGrid.show()`, `ShipGrid.hide()`, `ShipGrid.isAnimating()`, `ShipGrid.destroy()` — used consistently in all tasks. Event shapes `{type=string, slot=number}` consistent across server emit (Tasks 1–4) and client drain (Task 15). `combat.events` field name consistent across server (Tasks 1–5) and client (Task 15).
