# Restart-Flow Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the Apple II "Restart?" / abandon-ship flow so the confirmation matches the standard type-and-Enter prompt style and the post-abandon message sits at the bottom of a status screen.

**Architecture:** Two function rewrites plus one dispatch-line edit, all in `PromptEngine.luau`. `sceneRestartConfirm` becomes a `type` (Enter-to-submit) prompt rendered over the live at-port screen; `sceneAbandonMessage` renders over the port status screen with the message in the comprador area. No server, remotes, or shared-logic changes.

**Tech Stack:** Luau, Roblox StarterGui, Azul sync, Apple II terminal prompt engine.

## Global Constraints

- Edit only `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`. No server / remotes / shared changes.
- Apple II interface only; Modern interface untouched.
- Colour constants already in-module: `AMBER`, `GREEN` (do not redefine).
- Inverted text uses segment field `inverted = true`.
- No automated test exists for this module: `PromptEngine` is a StarterGui module and the TestEZ suite is server-side (Studio Run mode). **Verification is manual in Studio Play, Apple II interface.**
- Confirm question string is exactly `"Will you abandon your ship, Taipan? "` (note the single trailing space; 36 chars). Only the question text is inverted, not padding.
- Reference spec: `docs/superpowers/specs/2026-06-29-restart-flow-polish-design.md`.

---

## File Structure

- **Modify** `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau`:
  - `sceneAbandonMessage` (~lines 545-558) — message over port status screen.
  - `sceneRestartConfirm` (~lines 601-620) — standardized type-and-Enter confirm over the at-port screen; gains `playSound` param.
  - `processState` dispatch for `"restart_confirm"` (~line 1669) — pass `playSound`.

No new files.

---

### Task 1: `sceneAbandonMessage` — message at bottom of status screen

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (~545-558)

**Interfaces:**
- Consumes: `buildPortRows(state)` (existing module-local function, returns a `rows` table populated for rows 1-16), `AMBER`, `localSceneCb`.
- Produces: `sceneAbandonMessage(state, _actions, localSceneCb)` — unchanged signature and return shape (`{ rows = rows }, promptDef`); now reads `state` (was `_state`).

- [ ] **Step 1: Replace the function body**

Current code (to replace):

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

New code:

```lua
local function sceneAbandonMessage(state, _actions, localSceneCb)
  -- Keep the port status (rows 1-16) visible; clear the comprador area and show
  -- the parting message there, mirroring the combat "buggers got us" status
  -- screen rather than a fully blanked screen. setGameOver preserves cash/ship/
  -- port, so buildPortRows renders correctly.
  local rows = buildPortRows(state)
  for r = 17, 24 do rows[r] = { text = "", color = AMBER } end
  rows[19] = { text = "Ashamed of your failure, you disappear", color = AMBER }
  rows[20] = { text = "into the night, never to be seen again.", color = AMBER }
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

- [ ] **Step 2: Confirm `buildPortRows` is in scope above this function**

Run: search the file for `local function buildPortRows`.
Expected: it is defined earlier in the file (well above line 545), so the upvalue reference resolves. (It is used the same way by `sceneRepair`, `sceneBuyOverloadErr`, etc.) No code change needed — this is a verification step.

- [ ] **Step 3: Manual verification in Studio Play (Apple II)**

1. Start Play, choose Apple II interface, start a game, travel/trade until at Hong Kong with net worth < 1,000,000.
2. Press `R`, then `Y`, then Enter to abandon (Task 2 makes this prompt; for this task alone you may temporarily trigger abandon however is convenient, e.g. via the existing confirm, then return).
3. Expect: the top port status block (firm/date/location, hold box, cash/bank) rows 1-16 remain visible; rows 17-24 are blank except:
   - Row 19: `Ashamed of your failure, you disappear`
   - Row 20: `into the night, never to be seen again.`
4. Press any key → final status screen appears as before.

Note: there is no automated test for this module; this manual check is the verification.

- [ ] **Step 4: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "$(cat <<'EOF'
Render abandon "Ashamed" message over port status screen

Keep port status rows 1-16 visible and place the parting message in the
comprador area (rows 19-20) instead of a fully blanked screen, mirroring the
combat "buggers got us" status pattern.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `sceneRestartConfirm` — standardized type-and-Enter confirm + dispatch

**Files:**
- Modify: `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` (~601-620 and ~1669)

**Interfaces:**
- Consumes: `buildPortRows(state)`, `pad(str, width)` (existing module-local helper used by `sceneAtPort`), `AMBER`, `GREEN`, `actions.abandonShip()`, `localSceneCb`, `playSound(name)`.
- Produces: `sceneRestartConfirm(_state, actions, localSceneCb, playSound)` — gains 4th param `playSound`; return shape unchanged (`{ rows = rows }, promptDef`).

- [ ] **Step 1: Replace the function body**

Current code (to replace):

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

New code:

```lua
local ABANDON_CONFIRM_Q = "Will you abandon your ship, Taipan? "  -- 36 chars

local function buildAbandonConfirmRow(s)
  -- Question text inverted to attract attention; the typed echo (with caret)
  -- stays in normal video.
  return { segments = {
    { text = ABANDON_CONFIRM_Q, color = AMBER, inverted = true },
    { text = s,                 color = AMBER },
  }}
end

local function sceneRestartConfirm(state, actions, localSceneCb, playSound)
  -- Keep the at-port screen (status + prices) visible behind the confirmation:
  -- same comprador layout as sceneAtPort, with the question on row 23 and row 24
  -- blank. Standardized as a type-and-Enter prompt (no literal "(Y/N)").
  local rows   = buildPortRows(state)
  local prices = state.currentPrices or {0, 0, 0, 0}
  local p1 = tostring(math.floor(prices[1]))
  local p2 = tostring(math.floor(prices[2]))
  local p3 = tostring(math.floor(prices[3]))
  local p4 = tostring(math.floor(prices[4]))

  rows[17] = { text = "Comprador's Report",                              color = AMBER }
  rows[18] = { text = "",                                                color = AMBER }
  rows[19] = { text = "Taipan, present prices per unit here are",        color = AMBER }
  rows[20] = { text = "   Pepper: " .. pad(p1, 7) .. "Silk: " .. p2,   color = GREEN }
  rows[21] = { text = "   Arms: "   .. pad(p3, 9) .. "General: " .. p4, color = GREEN }
  rows[22] = { text = "",                                                color = AMBER }
  rows[23] = buildAbandonConfirmRow("")
  rows[24] = { text = "",                                                color = AMBER }

  return { rows = rows }, {
    type            = "type",
    maxLength       = 1,
    typePlaceholder = "",
    _inputRow       = 23,
    _buildInputRow  = buildAbandonConfirmRow,
    onType = function(text, _s, _a)
      local c = (text or ""):upper()
      if c == "Y" then
        actions.abandonShip()
        return nil
      elseif c == "N" then
        if localSceneCb then localSceneCb(nil) end
        return nil
      end
      -- empty / whitespace / any other char: re-prompt in place with bad joss
      if playSound then playSound("badjoss") end
      return nil
    end,
  }
end
```

- [ ] **Step 2: Update the dispatch to pass `playSound`**

Find (~line 1669):

```lua
  if localScene == "restart_confirm" then return sceneRestartConfirm(state, actions, localSceneCb) end
```

Replace with:

```lua
  if localScene == "restart_confirm" then return sceneRestartConfirm(state, actions, localSceneCb, playSound) end
```

- [ ] **Step 3: Verify helper upvalues are in scope**

Run: search the file for `local function pad(` and `local function buildPortRows`.
Expected: both are defined earlier in the file (used by `sceneAtPort`), so the upvalue references resolve. `playSound` is the 6th parameter of `processState` and is already threaded to `sceneFirmName`. Verification step only — no code change.

- [ ] **Step 4: Manual verification in Studio Play (Apple II)**

1. Start Play → Apple II → start a game → reach Hong Kong with net worth < 1,000,000.
2. Press `R`.
   - Expect: port status (rows 1-16) and the comprador price block (rows 17-22) stay visible; row 23 shows inverted `Will you abandon your ship, Taipan? ` followed by a caret; no `(Y/N)`; row 24 blank.
3. Press `N`, then Enter → returns to the port trade screen (`sceneAtPort`).
4. Press `R` again; press `X` (or any non-Y/N key) then Enter, and separately press Enter on an empty field → each plays `badjoss` and the prompt stays in place (screen unchanged).
5. Press `R`, then `Y`, then Enter → abandons: port status rows 1-16 remain, rows 17-24 clear except the "Ashamed…" message on rows 19-20 (from Task 1). Any key → final status.
6. Confirm lowercase works: `R`, `y`, Enter also abandons.

Note: manual verification only; no automated test for this module.

- [ ] **Step 5: Commit**

```bash
git add sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau
git commit -m "$(cat <<'EOF'
Standardize abandon-ship confirm to type-and-Enter prompt

Render the confirmation over the live at-port screen (status + prices), with
the question "Will you abandon your ship, Taipan?" inverted on row 23 and row
24 blank. Replace the instant Y/N keypress with a type-and-Enter prompt
(maxLength 1, no literal "(Y/N)"); empty/invalid input replays bad joss and
re-prompts in place. Thread playSound through the restart_confirm dispatch.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- Standardize confirm to type-and-Enter, no `(Y/N)` → Task 2 (`type = "type"`, `maxLength = 1`, no `(Y/N)` string).
- Reword to "Will you abandon your ship, Taipan?" on one line → Task 2 (`ABANDON_CONFIRM_Q`, single row 23).
- Invert question text (text only) → Task 2 (`buildAbandonConfirmRow`, `inverted = true` on question segment only).
- Keep port screen + prices, question on line 23, blank line 24 → Task 2 (`buildPortRows` + comprador rows 17-22, row 23 question, row 24 blank).
- "Ashamed" message at bottom of status screen → Task 1 (`buildPortRows`, message rows 19-20).
- Dispatch passes `playSound` → Task 2 Step 2.
- Out of scope (`sceneQuitConfirm`, Modern) → not touched. ✓

**Placeholder scan:** No TBD/TODO; all code blocks are complete and concrete. ✓

**Type consistency:** `buildAbandonConfirmRow` defined and referenced consistently in Task 2 (used for `rows[23]` and `_buildInputRow`). `sceneRestartConfirm` signature `(state, actions, localSceneCb, playSound)` matches the dispatch call in Step 2. `sceneAbandonMessage(state, _actions, localSceneCb)` matches its existing call site (`processState` already calls it with `(state, actions, localSceneCb)`). Helpers `buildPortRows`, `pad` referenced match existing module definitions. ✓

**Ordering note:** Task 1 (abandon message) is independent and verifiable on its own. Task 2's full abandon-path check depends on Task 1 being in place for the final "Ashamed" screen, but the confirm-prompt rendering and N/invalid paths verify without it.
