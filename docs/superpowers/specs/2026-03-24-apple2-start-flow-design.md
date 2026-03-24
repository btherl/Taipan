# Apple II Start Flow Design

**Date:** 2026-03-24
**Branch:** feature/apple2-interface
**Status:** Approved

## Goal

New players should first choose their interface (Apple II or Modern), then see the start choice screen ("Do you have a firm, or a ship?") rendered by their chosen interface. Returning players with a saved game skip both screens entirely and land directly at their saved state, using the interface stored in their save.

## Problem

`SetUIMode` currently requires existing server state (guarded by `type(state) ~= "table"`), but the Apple II start choice must be shown *before* state exists. The bootstrapper cannot create `Apple2Interface` until it knows the mode, and it cannot know the mode until `SetUIMode` is acknowledged — creating a chicken-and-egg dependency.

## Solution: Early load on connect + server-side pending mode + immediate adapter creation

The server attempts a DataStore load inside `PlayerAdded`. If a save is found, it pushes state immediately — the client receives a `StateUpdate` with `uiMode` set, destroys the picker, and goes straight to the saved game. No `ChooseStart` needed for returning players.

For new players the DataStore miss produces nothing. The bootstrapper keeps the picker visible. When the player picks an interface, `onPicked` fires immediately: the adapter is created, `SetUIMode` stores the choice in a `pendingModes` table (since no state exists yet), and — for Apple II — `update({})` renders `sceneStartChoice`. When the player presses F/S, `ChooseStart` creates the new game and applies the pending mode before `pushState`.

## Changes

### 1. `GameService.server.lua`

Add `pendingModes: {[Player]: string} = {}` alongside `playerStates`.

**`PlayerAdded` handler** — attempt DataStore load immediately after cloning StarterGui:
```lua
task.spawn(function()
  local loaded = loadPlayer(player)
  if loaded then
    playerStates[player] = loaded
    pushState(player)
  end
  -- new player: do nothing, wait for ChooseStart
end)
```

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

**`ChooseStart` handler** — returning players now have their state set by `PlayerAdded`, so the sentinel guard (`if playerStates[player] then return end`) silently drops any `ChooseStart` they send. Only new players reach the body. Apply the pending mode before `pushState` in the new-game branch:

```lua
-- new-game branch only (returning players are no-op'd by the sentinel guard):
if pendingModes[player] then
  state.uiMode = pendingModes[player]
  pendingModes[player] = nil
end
playerStates[player] = state
pushState(player)
```

The DataStore load previously in `ChooseStart` is now done in `PlayerAdded`, so the loaded-save branch in `ChooseStart` is removed.

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

`StateUpdate` handler: `StateUpdate` can now arrive while `currentMode == "picker"` — when a returning player's save is found in `PlayerAdded` and pushed immediately. The existing `currentMode == "picker"` + `targetMode ~= nil` branch already handles this: it destroys the picker and creates the correct adapter. For new players, `StateUpdate` only arrives after `ChooseStart` (by which time `currentMode` is already set by `onPicked`). Live interface switching is still handled by the `targetMode ~= currentMode` branch.

### 4. `Apple2Interface.lua`

One line change in `render()` — pass `state or {}` to `PromptEngine.processState`:

```lua
local lines, promptDef = PromptEngine.processState(state or {}, scene, actions, ...)
```

This is a defensive guard: in the designed flow `update({})` is always called (not `update(nil)`), so `state` inside `render()` is already `{}`. The `or {}` protects against future nil calls without changing current behaviour.

### 5. `PromptEngine.lua` — update stale comment only

Lines 660–661 contain a comment that is now incorrect:
```lua
-- InterfacePicker handles this before Apple2Interface is created,
-- so state.startChoice is always set on arrival
```
Replace with:
```lua
-- Fires when startChoice is nil (pre-choice) — including the initial update({})
-- call from the bootstrapper before ChooseStart has been sent.
```

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

### Returning player (any interface)

1. Player connects → server's `PlayerAdded` fires → DataStore load succeeds → `pushState(player)`
2. Client receives `StateUpdate` while `currentMode == "picker"` → `state.uiMode` is set → picker destroyed → correct adapter created → `adapter.update(savedState)` → saved scene renders ✓
3. Player never interacts with InterfacePicker or the start choice screen

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
| `src/ServerScriptService/GameService.server.lua` | Add `pendingModes`; early load in `PlayerAdded`; update `SetUIMode`, `ChooseStart`, `PlayerRemoving` handlers |
| `src/StarterGui/TaipanGui/InterfacePicker.lua` | Remove Phase 2; add `onPicked` callback param |
| `src/StarterGui/TaipanGui/init.client.lua` | Pass `onPicked` to picker; immediate adapter creation |
| `src/StarterGui/TaipanGui/Apple2Interface.lua` | Pass `state or {}` to PromptEngine |
| `src/StarterGui/TaipanGui/Apple2/PromptEngine.lua` | Update stale comment at lines 660–661 |
