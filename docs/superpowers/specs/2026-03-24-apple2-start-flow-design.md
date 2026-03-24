# Apple II Start Flow Design

**Date:** 2026-03-24
**Branch:** feature/apple2-interface
**Status:** Approved

## Goal

When a player selects the Apple II interface, they should see the Apple II terminal-style start choice screen ("Do you have a firm, or a ship?") before gameplay begins — not jump straight to port. Returning players with a saved game still see the start choice screen (faithful to the original Apple II game), but their F/S keypress merely triggers the DataStore load; the saved state overrides any start choice.

## Problem

`SetUIMode` currently requires existing server state (guarded by `type(state) ~= "table"`), but the Apple II start choice must be shown *before* state exists. The bootstrapper cannot create `Apple2Interface` until it knows the mode, and it cannot know the mode until `SetUIMode` is acknowledged — creating a chicken-and-egg dependency.

## Solution: Server-side pending mode + immediate adapter creation

Accept `SetUIMode` before state exists by storing the choice in a `pendingModes` table. When `ChooseStart` fires and creates or loads state, the pending mode is applied before `pushState`. The bootstrapper creates the adapter immediately when Phase 1 is picked (via an `onPicked` callback), calls `update({})` on Apple2Interface to show `sceneStartChoice`, then lets the real `StateUpdate` transition to the correct scene.

## Changes

### 1. `GameService.server.lua`

Add `pendingModes: {[Player]: string} = {}` alongside `playerStates`.

**`SetUIMode` handler** — remove the state-existence guard; always store the mode (retain existing input validation):
```lua
if mode ~= "modern" and mode ~= "apple2" then return end
pendingModes[player] = mode
local state = playerStates[player]
if type(state) == "table" then
  state.uiMode = mode
  savePlayer(player, state)
  pushState(player)
end
```

**`ChooseStart` handler** — apply pending mode just before each `pushState` call (both the "loaded save" and "new game" branches):
```lua
if pendingModes[player] then
  state.uiMode = pendingModes[player]
  pendingModes[player] = nil
end
pushState(player)
```

**`PlayerRemoving` handler** — add `pendingModes[player] = nil`.

### 2. `InterfacePicker.lua`

Remove Phase 2 entirely. Phase 1 accepts an `onPicked(mode)` callback (third constructor argument) and calls it when the player picks an interface. `update(_state)` becomes a no-op.

```lua
function InterfacePicker.new(screenGui, actions, onPicked)
  -- Phase 1 only; calls onPicked(mode) on selection
```

### 3. `init.client.lua` (bootstrapper)

Pass `onPicked` callback to InterfacePicker. On pick, immediately create the right adapter and fire `SetUIMode`:

```lua
local currentAdapter = InterfacePicker.new(screenGui, GameActions, function(mode)
  currentAdapter.destroy()
  GameActions.setUIMode(mode)          -- server stores pendingMode

  if mode == "apple2" then
    currentAdapter = Apple2Interface.new(screenGui, GameActions)
    currentMode    = "apple2"
    currentAdapter.update({})          -- empty state → sceneStartChoice
  else -- "modern"
    currentAdapter = ModernInterface.new(screenGui, GameActions)
    currentMode    = "modern"
    -- no update() — StartPanel shows from constructor
  end
end)
```

`StateUpdate` handler: in the new design, `StateUpdate` never arrives while `currentMode == "picker"` (the server only fires StateUpdate after `ChooseStart`, which happens after `onPicked` already set `currentMode`). The `currentMode == "picker"` branch in the handler becomes dead code and can be simplified. Live interface switching (changing mode from settings after game start) is still handled by the `targetMode ~= currentMode` branch.

### 4. `Apple2Interface.lua`

One line change in `render()` — pass `state or {}` to `PromptEngine.processState`:

```lua
local lines, promptDef = PromptEngine.processState(state or {}, scene, actions, ...)
```

This is a defensive guard: in the designed flow `update({})` is always called (not `update(nil)`), so `state` inside `render()` is already `{}`. The `or {}` protects against future nil calls without changing current behaviour.

### Note: `PromptEngine.lua` — no change needed

The full guard for `sceneStartChoice` is:
```lua
if state.startChoice == nil and (state.turnsElapsed or 1) == 1 and (state.destination or 0) == 0 then
```
An empty table `{}` satisfies all three conditions (`nil`, `1`, `0`), so `sceneStartChoice` renders correctly when `update({})` is called. Once `ChooseStart` creates real state (`startChoice` is set), the guard suppresses this scene on subsequent `StateUpdate` calls.

## Flow Walkthrough

### New player, picks Apple II

1. InterfacePicker Phase 1 → picks Apple II → `onPicked("apple2")`
2. Bootstrapper destroys picker, fires `SetUIMode("apple2")` → server stores `pendingModes[player] = "apple2"`
3. Bootstrapper creates `Apple2Interface`, calls `update({})` → `sceneStartChoice` renders in terminal
4. Player presses **F** or **S** → `ChooseStart("cash"/"guns")` fires
5. Server creates fresh state, applies `pendingModes` → `state.uiMode = "apple2"`, `state.startChoice = "cash"` → `pushState`
6. `StateUpdate` arrives; `currentMode == "apple2"` already → `adapter.update(state)` → `sceneAtPort` renders ✓

### Returning player, picks Apple II

Steps 1–3 same as above (player sees start choice screen; this is faithful to original Apple II game).

4. Player presses **F** or **S** (choice doesn't affect loaded save)
5. Server loads saved state, applies `pendingModes` → `state.uiMode = "apple2"` (overrides any old saved mode) → `pushState`
6. `StateUpdate` arrives → `adapter.update(savedState)` → `sceneAtPort` (or wherever they left off) ✓

### New player, picks Modern

1. InterfacePicker Phase 1 → picks Modern → `onPicked("modern")`
2. Bootstrapper destroys picker, fires `SetUIMode("modern")` → server stores `pendingModes[player] = "modern"`
3. Bootstrapper creates `ModernInterface` (no `update()` call) → `StartPanel` visible by default
4. Player clicks cash/guns in `StartPanel` → `ChooseStart` fires
5. Server creates state, applies pendingMode → `state.uiMode = "modern"` → `pushState`
6. `StateUpdate` → `adapter.update(state)` → `startPanel.hide()`, port panels shown ✓

## Files Changed

| File | Change |
|------|--------|
| `src/ServerScriptService/GameService.server.lua` | Add `pendingModes`; update `SetUIMode`, `ChooseStart`, `PlayerRemoving` handlers |
| `src/StarterGui/TaipanGui/InterfacePicker.lua` | Remove Phase 2; add `onPicked` callback param |
| `src/StarterGui/TaipanGui/init.client.lua` | Pass `onPicked` to picker; immediate adapter creation |
| `src/StarterGui/TaipanGui/Apple2Interface.lua` | Pass `state or {}` to PromptEngine |
