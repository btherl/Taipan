# Design — Restart-game flow polish (Apple II)

**Date:** 2026-06-29
**Scope:** `sync/StarterGui/TaipanGui/GameController/Apple2/PromptEngine.luau` only. No server, remotes, or shared-logic changes.
**Interface:** Apple II retro terminal only.

## Goal

Polish the "Restart?" / abandon-ship flow so it matches the visual conventions of the rest of the Apple II interface:

1. Standardize the abandon confirmation to the same input style as other prompts: no literal `(Y/N)`, type the choice, **Enter to confirm**.
2. Reword the question to **"Will you abandon your ship, Taipan?"** on a single line.
3. **Invert** the question text to draw attention.
4. Keep the port screen (status + prices) visible behind the confirmation: write the question on **line 23**, blank **line 24**.
5. Show the post-abandon **"Ashamed of your failure…"** message at the bottom of a status screen (like the combat "The buggers got us, Taipan!!!" message), rather than on a fully blanked screen.

## Background — current behavior

- `sceneRestartConfirm` (PromptEngine.luau ~601): blanks all 24 rows, splits the question across rows 22–23, shows literal `(Y/N)`, and fires instantly on a single `Y`/`N` keypress (`type = "key"`).
- `sceneAbandonMessage` (PromptEngine.luau ~545): blanks all 24 rows and centers the two-line message at rows 11–12.
- Reached via: `sceneAtPort` (non-retire HK) → `R` → `localSceneCb("restart_confirm")` → confirm → `actions.abandonShip()` → server `setGameOver(state, "abandoned")` → `processState` routes `"abandoned"` to `sceneAbandonMessage`, then any key → `final_status` → `sceneFinalStatus`.
- `setGameOver` preserves all canonical state (cash, ship, `currentPort`, prices); it only sets the gameOver flags and clears combat/`shipOffer`/`pendingArrival`. So `buildPortRows(state)` renders the full port status correctly after abandon.

## Reference patterns (already in the codebase)

- **Status-screen-with-bottom-message:** `sceneBuyOverloadErr`, `sceneRepairAmountErr` — `buildPortRows(state)` for rows 1–16, comprador report header at row 17, message in the 19–24 area.
- **Type-and-Enter input row:** `sceneFirmName` — `type = "type"`, `_inputRow`, `_buildInputRow`, `onType` returning `nil` to re-prompt in place, `playSound("badjoss")` for rejected input, threaded a `playSound` parameter from `processState`.
- **At-port comprador layout:** `sceneAtPort` — rows 17–22 = `Comprador's Report` / blank / `Taipan, present prices per unit here are` / `Pepper…Silk` / `Arms…General` / blank.
- **Inverted text:** segments with `inverted = true` (e.g. `buildPortRows` debt value, `sceneFinalStatus` score line).

## Changes

### 1. `sceneRestartConfirm` — standardized confirm prompt

Signature gains `playSound` (4th param), mirroring `sceneFirmName`.

Build the at-port layout so the port status and prices stay visible:

- Rows 1–16: `buildPortRows(state)`.
- Row 17: `Comprador's Report` (AMBER).
- Row 18: blank.
- Row 19: `Taipan, present prices per unit here are` (AMBER).
- Row 20: `   Pepper: <p1>      Silk: <p2>` (GREEN) — same formatting as `sceneAtPort` (left column padded to 18).
- Row 21: `   Arms: <p3>        General: <p4>` (GREEN).
- Row 22: blank.
- Row 23: the confirmation question (see below).
- Row 24: blank.

Confirmation question / input row (`_inputRow = 23`):

```lua
local CONFIRM_Q = "Will you abandon your ship, Taipan? "  -- 36 chars
local function buildAbandonConfirmRow(s)
  return { segments = {
    { text = CONFIRM_Q, color = AMBER, inverted = true },  -- question text only inverted
    { text = s,         color = AMBER },                   -- typed echo + caret, normal video
  }}
end
```

- `rows[23] = buildAbandonConfirmRow("")` for the initial render; `_buildInputRow = buildAbandonConfirmRow` keeps it in sync as the player types.
- Question text only is inverted (not padded to full width).

Prompt definition:

```lua
return { rows = rows }, {
  type           = "type",
  maxLength      = 1,
  typePlaceholder = "",
  _inputRow      = 23,
  _buildInputRow = buildAbandonConfirmRow,
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
```

Notes:
- `maxLength = 1` limits the field to a single character; Enter submits (`type = "type"` behavior).
- `Y` → `actions.abandonShip()`; the resulting `pushState` re-renders into the abandon path (no `localSceneCb` needed — `processState` for `"abandoned"` ignores the stale `restart_confirm` localScene and returns `sceneAbandonMessage`).
- `N` → `localSceneCb(nil)` returns to the port screen.
- Empty/invalid → `badjoss` and re-prompt in place (`onType` returns `nil`, scene unchanged). On mobile this re-summons the keyboard via the existing `KeyInput` refocus fix; on desktop the prompt simply stays active.
- Case-insensitive (`y`/`n` accepted).

### 2. `sceneAbandonMessage` — message at bottom of status screen

Use `state` (currently `_state`) for `buildPortRows`. Keep port status lines 1–16 visible; clear rows 17–24; place the two-line message in the comprador report area at rows 19–20.

```lua
local function sceneAbandonMessage(state, _actions, localSceneCb)
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

### 3. Dispatch — pass `playSound`

`processState` (PromptEngine.luau ~1669): pass `playSound` to `sceneRestartConfirm`, matching the `sceneFirmName` call:

```lua
if localScene == "restart_confirm" then return sceneRestartConfirm(state, actions, localSceneCb, playSound) end
```

## Out of scope

- `sceneQuitConfirm` keeps its `(Y/N)` style — this work covers the restart/abandon flow only.
- Modern interface — unchanged.

## Testing / verification

No automated test: `PromptEngine` is a StarterGui module, unreachable by the server-side TestEZ suite. Verify in Studio Play (Apple II interface):

1. New game → trade at non-retirement HK → press `R`.
   - Expect: port status + prices still visible; row 23 shows inverted `Will you abandon your ship, Taipan?` with a caret; no `(Y/N)`; row 24 blank.
2. Press `N`, Enter → returns to the port trade screen.
3. Press `R` again, press a non-Y/N char (e.g. `X`) or Enter with empty field → `badjoss` plays, prompt stays in place.
4. Press `Y`, Enter → abandon: port status lines 1–16 remain visible, rows 17–24 clear except `Ashamed of your failure, you disappear` / `into the night, never to be seen again.` at rows 19–20.
5. Any key → final status screen renders as before.
6. (Mobile, if available) the abandon-confirm keyboard re-summons after an invalid/empty submit (existing KeyInput refocus fix).
