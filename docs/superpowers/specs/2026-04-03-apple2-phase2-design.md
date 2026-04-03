# Apple2 Interface — Phase 2 Design

**Date:** 2026-04-03
**Source:** `docs/apple2_plans_2026_04_02.md`
**Status:** Approved

---

## Overview

This spec covers the remaining Apple2 interface scenes and behaviours not yet implemented after Phase 1. The core additions are:

1. A timed **notification queue** that plays event messages sequentially before the main scene renders.
2. Server-side **notification generation** for all travel events.
3. A redesigned **combat screen** matching the Apple II layout.
4. A **retirement flow** (millionaire marquee → final status screen).
5. A **numeric input type** in KeyInput (digits-only, left-arrow-to-delete).
6. A sequential **bank flow** (deposit then withdraw, no menu).

---

## Screen Layout Reminder

- Rows 1–16: status screen (unchanged — `buildPortRows` already populates these)
- Rows 17–24: prompt/notification area (8 lines)
- **Exceptions:** full-screen during retirement final status screen

---

## 1. Notification Queue (Apple2Interface.lua)

### How it works

`adapter.update(state)` extracts `state.pendingMessages` (an ephemeral array, never persisted) and appends entries to a module-local queue before running the normal render path.

Each queue entry:

```lua
{
  rows     = { [17] = lineTable, [18] = lineTable, ... },  -- rows 17–24
  duration = number,   -- seconds before auto-advance
}
```

Processing:

1. On each `adapter.update`, check for `state.pendingMessages`. If present, append all entries to `notifQueue`. Clear `state.pendingMessages` (or just ignore it after reading — it's ephemeral).
2. If `notifQueue` is non-empty, call `playNextNotif()` instead of `render()`.
3. `playNextNotif()`:
   - Increments `notifGen` (generation counter — prevents stale `task.delay` callbacks).
   - Pops the first entry, writes rows 17–24 via `term.showInputAt`.
   - Clears KeyInput (`ki.setPrompt(nil, ...)`).
   - Schedules `task.delay(entry.duration, advanceFn)` where `advanceFn` checks generation before proceeding.
   - Sets a one-shot keypress handler so any key also advances (calls `advanceFn` immediately).
4. `advanceFn`: if `notifQueue` is non-empty, call `playNextNotif()`. Otherwise call `render(lastState, localScene)`.

### Generation counter pattern

```lua
local notifGen    = 0
local notifQueue  = {}

local function advanceNotif(gen)
  if gen ~= notifGen then return end   -- stale callback, ignore
  if #notifQueue > 0 then
    playNextNotif()
  else
    render(lastState, localScene)
  end
end

local function playNextNotif()
  notifGen += 1
  local myGen = notifGen
  local entry = table.remove(notifQueue, 1)
  for r = 17, 24 do
    term.showInputAt(r, entry.rows[r] or { text = "", color = GREEN })
  end
  -- keypress skips
  ki.setPrompt({
    type = "key",
    keys = { "any" },
    onKey = function() advanceNotif(myGen) end,
  }, lastState, actions)
  task.delay(entry.duration, function() advanceNotif(myGen) end)
end
```

`"any"` key handling: KeyInput needs a small addition — if `promptDef.keys = {"any"}`, accept any key. This keeps the skip logic simple.

### adapter.notify

`adapter.notify(message)` is retained unchanged for the modern UI path. Apple2 ignores it — its notifications come from `pendingMessages` only.

---

## 2. Server-Side Notification Helpers (GameService.server.lua)

### Helper functions

Two helpers build `pendingMessages` entries. Both return a single entry table.

```lua
-- lines: array of strings (content lines, row 19 onward)
-- duration: seconds
local function makeCaptainNotif(lines, duration)
  local rows = {}
  rows[17] = { text = "  Captain's Report", color = AMBER }
  rows[18] = { text = "", color = AMBER }
  for i, line in ipairs(lines) do
    rows[18 + i] = { text = line, color = AMBER }
  end
  for r = 17, 24 do
    if not rows[r] then rows[r] = { text = "", color = AMBER } end
  end
  return { rows = rows, duration = duration }
end

local function makeCompradorNotif(lines, duration)
  local rows = {}
  rows[17] = { text = "Comprador's Report", color = AMBER }
  rows[18] = { text = "", color = AMBER }
  for i, line in ipairs(lines) do
    rows[18 + i] = { text = line, color = AMBER }
  end
  for r = 17, 24 do
    if not rows[r] then rows[r] = { text = "", color = AMBER } end
  end
  return { rows = rows, duration = duration }
end
```

### Notification triggers during TravelTo

All notifications are appended to a local `pending` table during `TravelTo` processing, then assigned to `state.pendingMessages` before `pushState`.

| Event | Helper | Duration | Content |
|---|---|---|---|
| Arriving at port | Comprador | 3s | `"Arriving at " .. portName` |
| Li Yuen request (no protection) | Comprador | 5s | Three lines per plans doc |
| Price drop | Comprador | 5s | `"Taipan!!  The price of " .. good` / `"has dropped to " .. price .. "!!"` |
| Price rise | Comprador | 5s | Same but "risen" |
| Storm: initial | Captain | 5s | `"Storm, Taipan!!"` |
| Storm: survived | Captain | 5s | `"Storm, Taipan!!"` / `""` / `"    We made it!!"` |
| Storm: blown off course | Captain | 5s | `"We've been blown off course"` / `"to " .. newPort` |
| Li Yuen pirates (unprotected → combat) | Captain | auto | `"Li Yuen's pirates, Taipan!!"` — short delay, then combat state drives scene |
| Li Yuen pirates (protected) | Captain | 5s | `"Li Yuen's pirates, Taipan!!"` / `""` / `"Good joss!! They let us be!!"` |
| Battle incoming | Captain | 1s | `tostring(n) .. " hostile ships approaching, Taipan!!"` — then combat state takes over |
| Battle booty | Captain | 5s | `"We've captured some booty"` / `"It's worth " .. fmt(amount) .. "!"` |

**Storm sequencing note:** Storm currently fires two distinct events (hit, then result). These become two separate `pendingMessages` entries in order, so they display sequentially.

**Battle incoming note:** The 1-second notification is sufficient because `state.combat` will be set in the same state update. After the notification queue empties, `isServerDriven` detects `state.combat ~= nil` and routes to the combat scene automatically.

---

## 3. PromptEngine Changes

### 3a. sceneCombatLayout (replaces sceneCombat)

Layout uses rows 17–24 (via `lines.rows` return, same as `buildPortRows`). The status screen (rows 1–16) remains visible.

```
Row 17: "   N ships attacking, Taipan!  | We have"
Row 18: "Your orders are to: [action]   |  N guns"
Row 19: "                               +--------"
Row 20: "Current seaworthiness: [label] ([sw]%)"
Rows 21–24: ship grid (one "#" per living ship slot, "." for empty, 10 slots)
```

- `[action]` is blank initially; after F/R/T is pressed it shows the chosen word while narration plays.
- Right column (cols 32–40) shows `" We have"` on row 17 and `"  N guns"` on row 18.
- The `+--------` divider on row 19 uses the standard box character or plain ASCII.
- Ship grid rows 21–24: display up to 10 slots. Layout TBD (2 rows of 5, or 1 row of 10, or sprite rows — placeholder `#`/`.` for now).

**Combat narration** (fight sequence): After `F` is pressed:
1. Row 20 changes to `"Aye, we'll fight 'em, Taipan!"` (immediate).
2. After 2 seconds: `"We're firing on 'em, Taipan!"`.
3. After result arrives in next state update:
   - If ships sunk: `"Sunk N of the buggers, Taipan!"`
   - If all sunk: `"We got 'em all, Taipan!!"`
   - If none sunk: `"Couldn't sink any, Taipan."` (invented — fill in exact wording later)

The narration is handled in Apple2Interface (not PromptEngine) using `task.delay`, since it's purely a display animation that doesn't gate input.

### 3b. sceneMillionaire

Displayed when `gameOver=true` and `gameOverReason="retired"`, as the first step before `sceneFinalStatus`.

Uses rows 17–24. Per the plans: "lines 3–8 of the bottom section" (rows 19–24) form an entirely inverted 25-wide block centered in 40 cols. Rows 17–18 are blank (non-inverted). The text appears inside the inverted block:

```
Row 17: ""  (normal)
Row 18: ""  (normal)
Row 19: [inverted, 25 wide, centered] "                         "  (blank)
Row 20: [inverted, 25 wide, centered] " Y o u ' r e    a       "
Row 21: [inverted, 25 wide, centered] "                         "  (blank)
Row 22: [inverted, 25 wide, centered] " M I L L I O N A I R E !"
Row 23: [inverted, 25 wide, centered] "                         "  (blank)
Row 24: [inverted, 25 wide, centered] "                         "  (blank)
```

Keypress advances to `sceneFinalStatus`. No auto-advance (player must press a key).

### 3c. sceneFinalStatus

Full 24-row display (rows 1–24 all redrawn; status rows 1–16 are cleared/repurposed).

Content per plans doc:

```
Row 1:  "Your final status:"
Row 2:  ""
Row 3:  "Net Cash: X.XX Million"
Row 4:  ""
Row 5:  "Ship size: N units with N guns"
Row 6:  ""
Row 7:  "You traded for N years and N months"
Row 8:  ""
Row 9:  [inverted] "Your score is NNN."
Row 10: ""
Row 11: ""
Row 12: ""
Row 13: "Your Rating:"
Row 14: "+-------------------------------+"
Row 15: "|Ma Tsu         50,000 and over |"
Row 16: "|Master Taipan   8,000 to 49,999|"
Row 17: "|Taipan          1,000 to  7,999|"
Row 18: "|Compradore        500 to    999|"
Row 19: "|Galley Hand       less than 500|"
Row 20: "+-------------------------------+"
Row 21: ""
Row 22: "Play again? (Y/N)"
Row 23: ""
Row 24: ""
```

The achieved rating row is also inverted (detected by comparing `state.finalScore` to the rating thresholds).

Valid responses: `Y` (restartGame) or `N` (quitGame).

### 3d. sceneGameOver routing update

```lua
if state.gameOver then
  if state.gameOverReason == "retired" then
    if localScene == "final_status" then
      return sceneFinalStatus(state, actions, localSceneCb)
    end
    return sceneMillionaire(state, actions, localSceneCb)
      -- localSceneCb("final_status") on keypress
  end
  return sceneGameOver(state, actions, localSceneCb)  -- existing (sunk/quit)
end
```

### 3e. sceneBank — sequential flow

Remove the D/W/C menu. Replace with:

1. Show "How much will you deposit?" (numeric input, max 9 digits). Submit → `bankDeposit`. Then proceed to step 2.
2. Show "How much will you withdraw?" (numeric input, max 9 digits). Submit → `bankWithdraw`. Then return to port scene.

Submitting 0 (or empty) skips that step. Over-limit shows error for 5 seconds (or keypress) then repeats the same prompt — use the `_onError` path already wired in Apple2Interface.

### 3f. sceneWuAmount — switch to numeric type

Change `type = "type"` → `type = "numeric"`, add `maxDigits = 9`.

---

## 4. KeyInput — Numeric Type

New `promptDef.type = "numeric"` prompt:

| Behaviour | Detail |
|---|---|
| Accepted keys | Digits `0`–`9` only |
| Left arrow | Deletes last digit (same as backspace on `"type"`) |
| Backspace | Ignored |
| Enter | Submits current buffer |
| Escape | Submits empty string (caller interprets as cancel) |
| Max digits | `promptDef.maxDigits` (required parameter) |
| Display | Same cursor/blink logic as `"type"` |
| Mobile | Uses hidden TextBox with numeric keyboard hint if available; otherwise digit buttons |

Implementation: add a third branch in `ki.setPrompt` alongside the existing `"key"` and `"type"` branches.

---

## 5. Summary of File Changes

| File | Changes |
|---|---|
| `Apple2Interface.lua` | `notifQueue`, `notifGen`, `playNextNotif`, `advanceNotif`; `"any"` key support wired to notification skip |
| `KeyInput.lua` | New `"numeric"` branch in `ki.setPrompt`; `"any"` key support for notification skip |
| `PromptEngine.lua` | New: `sceneCombatLayout`, `sceneMillionaire`, `sceneFinalStatus`; changed: `sceneBank` (sequential), `sceneWuAmount` (numeric type), `sceneGameOver` routing |
| `GameService.server.lua` | `makeCaptainNotif`, `makeCompradorNotif` helpers; append to `pendingMessages` at each travel event |

---

## Open Questions / Deferred Details

- **Ship grid rows 21–24:** Exact layout (2×5, 1×10, or sprites) TBD — placeholder `#`/`.` text for now.
- **Combat narration exact wording** when no ships are sunk: invent placeholder, refine later.
- **Bank error display:** 5-second timed error before repeating prompt — may reuse the notification queue or a simpler local timer.
- **"Any key" in KeyInput:** Implementation detail — could be a sentinel value in the `keys` array, or a separate `promptDef.anyKey = true` flag. Either works; choose at implementation time.
