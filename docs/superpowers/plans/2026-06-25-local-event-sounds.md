# Local Event Sounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play the original Apple II game's `good_joss` sound on the eight client-side (local) rejection scenes that currently have no sound, faithful to the original.

**Architecture:** Each local error scene function in `PromptEngine.luau` declares its sound by adding `sound = "goodjoss"` to the result table it already returns. `Apple2Interface.render` reads that field and plays it via `SoundPlayer.play`, guarded by a `lastSoundedScene` dedup key so it fires exactly once per scene entry (not on every re-render keystroke). Scenes declare their own sound — rather than an external lookup table — because `sceneWarehouseNoCargo` is a state-conditional branch under `localScene == "warehouse"` and cannot be keyed by scene string alone.

**Tech Stack:** Roblox Luau. Client interface modules only. No new assets — reuses the existing `goodjoss` entry in `sync/ReplicatedStorage/Sounds.luau`. `SoundPlayer` is already required at `Apple2Interface.luau:13`.

**Spec:** `docs/superpowers/specs/2026-06-25-local-event-sounds-design.md`

**Testing note:** These are Roblox client UI modules; the TestEZ suite covers only pure `shared/` logic, so there is no automated test for this glue. Verification is manual via the Studio MCP tools. Per project guidance, **audio confirmation is the user's responsibility** (screen capture is silent) — the implementer drives the UI to each error state and confirms the correct scene renders; the user confirms the sound plays.

---

## File Structure

- **Modify:** `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` — add `sound = "goodjoss"` to the return value of eight error scene functions. No logic/dispatch changes.
- **Modify:** `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau` — declare `lastSoundedScene`; in `render`, play `lines.sound` once per scene entry.

The eight scenes and their `localScene` trigger keys (all map to `goodjoss`):

| Scene function | Trigger key | Trigger site |
|---|---|---|
| `sceneAlreadyHere` | `already_here` | travel to current port (`PromptEngine.luau:423`) |
| `sceneBuyOverloadErr` | `buy_overload_err` | buy past hold space (`:388`) |
| `sceneWuBorrowErr` | `wu_borrow_err` | borrow over limit (`:957`) |
| `sceneWuRepayErr` | `wu_repay_err` | repay over cash (`:1015`) |
| `sceneBankDepositErr` | `bank_deposit_err` | deposit over cash (`:1171`) |
| `sceneBankWithdrawErr` | `bank_withdraw_err` | withdraw over balance (`:1196`) |
| `sceneWarehouseStepErr` | `wh_err_N` | transfer over available (`:1328`) |
| `sceneWarehouseNoCargo` | `warehouse` + no cargo | transfer with empty hold+warehouse (`:1557`) |

---

## Task 1: Declare sound on the inline-return error scenes

Six scenes return a plain `{ rows = rows }` table. Add `, sound = "goodjoss"` inside that table. Each edit is anchored on the scene's distinctive preceding row text so it is unambiguous (the bare string `return { rows = rows }, {` appears in many non-error scenes — do **not** use a global find/replace).

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`

- [ ] **Step 1: `sceneAlreadyHere` (around line 442-443)**

Change:
```lua
  rows[24] = { text = "You're already here, Taipan.",               color = GREEN }
  return { rows = rows }, {
```
to:
```lua
  rows[24] = { text = "You're already here, Taipan.",               color = GREEN }
  return { rows = rows, sound = "goodjoss" }, {
```

- [ ] **Step 2: `sceneBuyOverloadErr` (around line 752-753)**

Change:
```lua
  for r = 20, 24 do rows[r] = { text = "", color = AMBER } end
  return { rows = rows }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, nil },
    onKey        = function() if localSceneCb then localSceneCb(nil) end end,
  }
end

local function sceneRepairAmountErr(state, _actions, localSceneCb)
```
to:
```lua
  for r = 20, 24 do rows[r] = { text = "", color = AMBER } end
  return { rows = rows, sound = "goodjoss" }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, nil },
    onKey        = function() if localSceneCb then localSceneCb(nil) end end,
  }
end

local function sceneRepairAmountErr(state, _actions, localSceneCb)
```

Note: only `sceneBuyOverloadErr` changes here. `sceneRepairAmountErr` (which follows) is intentionally left untouched — it has no original-game sound (a non-goal in the spec). The surrounding context above makes the target edit unambiguous.

- [ ] **Step 3: `sceneBankDepositErr` (around line 1210-1211)**

Change:
```lua
  rows[22] = { text = "in cash.",                                           color = GREEN }
  return { rows = rows }, {
```
to:
```lua
  rows[22] = { text = "in cash.",                                           color = GREEN }
  return { rows = rows, sound = "goodjoss" }, {
```

- [ ] **Step 4: `sceneBankWithdrawErr` (around line 1223-1224)**

Change:
```lua
  rows[22] = { text = "in the bank.",                                              color = GREEN }
  return { rows = rows }, {
```
to:
```lua
  rows[22] = { text = "in the bank.",                                              color = GREEN }
  return { rows = rows, sound = "goodjoss" }, {
```

- [ ] **Step 5: `sceneWarehouseNoCargo` (around line 1258-1259)**

Change:
```lua
  rows[24] = { text = "",                                                color = AMBER }
  return { rows = rows }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, nil },
    onKey        = function() if localSceneCb then localSceneCb(nil) end end,
  }
end
```
to:
```lua
  rows[24] = { text = "",                                                color = AMBER }
  return { rows = rows, sound = "goodjoss" }, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, nil },
    onKey        = function() if localSceneCb then localSceneCb(nil) end end,
  }
end
```

- [ ] **Step 6: `sceneWarehouseStepErr` (around line 1366-1367)**

This scene has an early `return sceneAtPort(...)` fallback at line 1348-1350 — leave that one alone (it is not an error display). Edit only the main return:

Change:
```lua
  local retScene = "wh_step_" .. stepN
  return { rows = rows }, {
```
to:
```lua
  local retScene = "wh_step_" .. stepN
  return { rows = rows, sound = "goodjoss" }, {
```

- [ ] **Step 7: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "Declare goodjoss sound on inline-return local error scenes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Declare sound on the Wu error scenes

`sceneWuBorrowErr` and `sceneWuRepayErr` return the result of `sceneWuLayout(...)` rather than an inline table, so capture that table into a local and set `.sound` on it before returning.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`

- [ ] **Step 1: `sceneWuBorrowErr` (around line 970-983)**

Change:
```lua
local function sceneWuBorrowErr(state, _actions, localSceneCb)
  return sceneWuLayout(state, {
    { text = "How much do you wish to",             color = AMBER },
    { text = "borrow?",                             color = AMBER },
    { text = "",                                    color = AMBER },
    { text = "He won't loan you so much, Taipan!", color = GREEN },
  }), {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "wu_borrow" },
    onKey        = function() if localSceneCb then localSceneCb("wu_borrow") end end,
  }
end
```
to:
```lua
local function sceneWuBorrowErr(state, _actions, localSceneCb)
  local lines = sceneWuLayout(state, {
    { text = "How much do you wish to",             color = AMBER },
    { text = "borrow?",                             color = AMBER },
    { text = "",                                    color = AMBER },
    { text = "He won't loan you so much, Taipan!", color = GREEN },
  })
  lines.sound = "goodjoss"
  return lines, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "wu_borrow" },
    onKey        = function() if localSceneCb then localSceneCb("wu_borrow") end end,
  }
end
```

- [ ] **Step 2: `sceneWuRepayErr` (around line 985-999)**

Change:
```lua
local function sceneWuRepayErr(state, _actions, localSceneCb)
  return sceneWuLayout(state, {
    { text = "How much do you wish to repay", color = AMBER },
    { text = "him?",                          color = AMBER },
    { text = "",                              color = AMBER },
    { text = "Taipan, you only have " .. fmtBig(state.cash or 0), color = GREEN },
    { text = "in cash.",                      color = GREEN },
  }), {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "wu_repay" },
    onKey        = function() if localSceneCb then localSceneCb("wu_repay") end end,
  }
end
```
to:
```lua
local function sceneWuRepayErr(state, _actions, localSceneCb)
  local lines = sceneWuLayout(state, {
    { text = "How much do you wish to repay", color = AMBER },
    { text = "him?",                          color = AMBER },
    { text = "",                              color = AMBER },
    { text = "Taipan, you only have " .. fmtBig(state.cash or 0), color = GREEN },
    { text = "in cash.",                      color = GREEN },
  })
  lines.sound = "goodjoss"
  return lines, {
    type         = "key",
    keys         = {},
    anyKey       = true,
    _autoAdvance = { 5, "wu_repay" },
    onKey        = function() if localSceneCb then localSceneCb("wu_repay") end end,
  }
end
```

- [ ] **Step 3: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "Declare goodjoss sound on Wu borrow/repay error scenes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Play the declared sound in render (with once-per-entry dedup)

Activate the `sound` fields: `Apple2Interface.render` reads `lines.sound` and plays it, guarded by `lastSoundedScene` so re-render keystrokes don't replay it.

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau`

- [ ] **Step 1: Declare the dedup state variable**

After line 82 (`local renderGen  = 0   -- ...`), add a new line:

Change:
```lua
  local renderGen  = 0   -- incremented each render; used to discard stale _autoAdvance callbacks
  local GREEN      = Color3.fromRGB(140, 200, 80)
```
to:
```lua
  local renderGen  = 0   -- incremented each render; used to discard stale _autoAdvance callbacks
  local lastSoundedScene = nil  -- localScene value whose sound we last played; dedups re-renders
  local GREEN      = Color3.fromRGB(140, 200, 80)
```

- [ ] **Step 2: Play the sound after processState returns**

In `render`, the `processState` call returns `lines, promptDef` (ends at the `)` on the line before `if lines.rows then`). Insert the sound block between them.

Change:
```lua
    if lines.rows then
      term.setRows(lines.rows)
```
to:
```lua
    -- Local-scene sound: a scene fn may set lines.sound (e.g. "goodjoss" on a
    -- rejection scene). Play it once per scene entry, not on every re-render
    -- keystroke. Dedup on localScene; clear the marker on any soundless scene so
    -- the same error can sound again after the player leaves and re-triggers it.
    if lines.sound and localScene ~= lastSoundedScene then
      lastSoundedScene = localScene
      local soundName = lines.sound
      task.spawn(function() SoundPlayer.play(soundName) end)  -- play() blocks; must spawn
    elseif not lines.sound then
      lastSoundedScene = nil
    end

    if lines.rows then
      term.setRows(lines.rows)
```

- [ ] **Step 3: Sync to Studio and confirm sizes match**

Per CLAUDE.md workflow: ensure the local edits propagated to Studio via Azul and the local/Studio copies match (size difference of at most 1 allowed). Use the MCP `script_read` / `inspect_instance` tools on `StarterGui.TaipanGui.GameController.Apple2Interface` and `...Apple2.PromptEngine` to confirm.

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2Interface.luau
git commit -m "Play local-scene sound once per entry in Apple2 render

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Manual verification of all eight triggers

No automated test exists for this client glue (see Testing note). Drive the Apple II UI to each error state via the Studio MCP tools and confirm the correct scene renders. The implementer verifies the visual scene; **the user verifies the sound plays** (screen capture is silent).

**Setup:** `start_stop_play(true)`, select the Apple II interface, choose a start (e.g. Firm/cash), arrive at Hong Kong.

- [ ] **Step 1: Drive each trigger and screen-capture the resulting scene**

| # | Trigger steps | Expected scene (row text) |
|---|---|---|
| 1 | `already_here` — open travel menu, choose the **current** port's number | "You're already here, Taipan." |
| 2 | `buy_overload_err` — buy a quantity of a good that exceeds remaining hold space | "You're ship is overloaded, Taipan!!" |
| 3 | `wu_borrow_err` — at HK Wu session, borrow more than Wu's limit | "He won't loan you so much, Taipan!" |
| 4 | `wu_repay_err` — at HK Wu session, repay more than current cash | "Taipan, you only have … in cash." |
| 5 | `bank_deposit_err` — at HK bank, deposit more than current cash | "Taipan, you only have … in cash." |
| 6 | `bank_withdraw_err` — at HK bank, withdraw more than balance | "Taipan, you only have … in the bank." |
| 7 | `wh_err_N` — at HK warehouse, transfer more of a good than is available | "You only have N, Taipan." |
| 8 | `warehouse` no cargo — at HK with empty hold **and** empty warehouse, open transfer | "You have no cargo, Taipan." |

For each: capture before and after, confirm the scene matches. Per CLAUDE.md note, treat keyboard digits as strings when reading state.

- [ ] **Step 2: Confirm the dedup behaves (no replay on re-render)**

For a numeric-entry error (e.g. #5 bank deposit over cash): after the error scene appears, it auto-advances or accepts a keypress back to the entry scene. Re-enter the bank scene and trigger the error again — the sound should play again (a soundless scene sits between the two errors, clearing `lastSoundedScene`). The user confirms the sound fires on each fresh entry and does **not** stutter/repeat within a single error display.

- [ ] **Step 3: Exit play mode**

`start_stop_play(false)`.

- [ ] **Step 4: Ask the user to confirm audio**

Explicitly ask the user to confirm each of the eight sounds played correctly, since audio cannot be verified from screen capture.

---

## Self-Review Notes

- **Spec coverage:** All eight goal scenes (Task 1: 6 inline + Task 2: 2 Wu) get `sound = "goodjoss"`; Task 3 wires playback with the dedup guard the spec requires. Non-goals (`repair_amount_err`, buy/sell over-limit silent-clear, empty firm name) are untouched — Step 2 of Task 1 explicitly leaves `sceneRepairAmountErr` alone.
- **`sceneWarehouseStepErr` early return:** its `return sceneAtPort(...)` fallback (line 1348-1350) is deliberately not given a sound — only the error display return is.
- **Type consistency:** the field is `sound` (string) everywhere; read as `lines.sound` in render; played via `SoundPlayer.play(soundName)` which already exists and accepts a name key from `Sounds.luau`.
