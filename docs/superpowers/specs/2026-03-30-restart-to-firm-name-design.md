# Design: Restart Returns to Firm Name Screen

**Date:** 2026-03-30
**Status:** Approved

## Problem

After any game ending (ship sunk, quit, or retired), the RESTART button currently creates a new game using the previous `startChoice` and skips the firm name screen. The player has no opportunity to rename their firm or change their start type (cash vs guns).

## Goal

After any game-over, both the Apple II and Modern UI return to the firm name screen, exactly as on a fresh first launch. The player re-enters a firm name and re-picks their start type before the new game begins.

## Approach

**Option A — Server sends a "lobby" state.** `RestartGame` pushes a minimal pre-game state (`startChoice=nil`) to the client. Existing client routing already treats `startChoice==nil` as "show firm name screen." The only new client work is making `StartPanel` re-showable (Modern UI) and resetting `localScene` on lobby arrival (Apple II).

Chosen because it keeps the server-authoritative, state-driven pattern intact. No new remotes, no imperative client-side resets.

---

## Design

### 1. Server — `GameService.server.lua`

#### RestartGame handler

Replaces the current handler, which built a full new game state from `prevStartChoice`. The new handler builds a minimal **lobby state** and pushes it:

```lua
Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.gameOver then return end
  playerStates[player] = {
    _isLobby     = true,
    startChoice  = nil,
    gameOver     = false,
    turnsElapsed = 1,
    destination  = 0,
    uiMode       = state.uiMode,
    seenTutorial = state.seenTutorial,
  }
  pushState(player)
end)
```

The `_isLobby` flag is used only server-side (DataStore save guard). The client never reads it.

#### ChooseStart guard

Changed from "block if any state exists" to "block if a real game is in progress":

```lua
local existing = playerStates[player]
if type(existing) == "boolean" then return end          -- sentinel during async load
if type(existing) == "table" and existing.startChoice ~= nil then return end
-- nil (new player) or lobby state → allowed through
```

This lets `ChooseStart` create a fresh game from either a nil slot (brand new player) or a lobby-state slot (restarting player). The rest of the `ChooseStart` handler is unchanged.

#### PlayerRemoving save guard

Skips the DataStore save when the player disconnects during the lobby (no serialisable game to preserve):

```lua
if type(state) == "table" and not state._isLobby then
  savePlayer(player, state)
end
```

---

### 2. Apple II — `Apple2Interface.lua`

One addition to `adapter.update`: reset `localScene` to nil when a lobby state arrives, so any lingering local scene from the previous game does not block the firm name scene:

```lua
function adapter.update(state)
  lastState = state
  if isServerDriven(state) then
    localScene = nil
  elseif state.startChoice == nil then   -- lobby state: reset to firm name
    localScene = nil
  end
  render(state, localScene)
end
```

**`PromptEngine.lua`: no changes.** Existing routing already handles `startChoice==nil`:

```lua
if state.startChoice == nil and (state.turnsElapsed or 1) == 1 and (state.destination or 0) == 0 then
  -- routes to sceneFirmName (or sceneStartChoice if localScene == "start_choice")
end
```

The lobby state satisfies all three conditions.

---

### 3. Modern UI — `StartPanel.lua` + `ModernInterface.lua`

#### StartPanel.lua

Change `panel.hide()` from destroying the frame to hiding it, and add `panel.show()`:

```lua
function panel.hide()
  frame.Visible = false
end

function panel.show()
  frame.Visible = true
end
```

Both methods are idempotent. The name text box retains its value between hide/show cycles, so the player sees a blank-or-previous name on restart (the box starts empty on first construction; they can clear and retype).

#### ModernInterface.lua

In `adapter.update`, detect the lobby state and show `StartPanel` instead of updating the game panels:

```lua
function adapter.update(state)
  if state.startChoice == nil and not state.gameOver then
    startPanel.show()
    return   -- state is incomplete; skip all panel updates
  end
  startPanel.hide()
  -- ... rest of existing update unchanged
end
```

The early return prevents `portPanel.update`, `statusStrip.update`, etc. from being called on a lobby state that lacks most fields.

---

## Data Flow

```
Player clicks RESTART (any ending)
  → actions.restartGame()
  → server RestartGame: creates lobby state, pushState
  → client StateUpdate: state.startChoice == nil, state.gameOver == false

  Apple II path:
    adapter.update → localScene = nil → render
    PromptEngine: startChoice==nil → sceneFirmName ✓

  Modern path:
    adapter.update → startChoice==nil → startPanel.show(), return ✓

Player enters firm name, picks start
  → actions.setFirmName(name), actions.chooseStart(choice)
  → server ChooseStart: lobby state present but startChoice==nil → allowed
  → creates real game state → pushState
  → normal game begins ✓
```

---

## Files Changed

| File | Change |
|---|---|
| `src/ServerScriptService/GameService.server.lua` | RestartGame handler, ChooseStart guard, PlayerRemoving save guard |
| `src/StarterGui/TaipanGui/Apple2Interface.lua` | `adapter.update`: reset localScene on lobby state |
| `src/StarterGui/TaipanGui/Panels/StartPanel.lua` | `panel.hide()` → Visible=false; add `panel.show()` |
| `src/StarterGui/TaipanGui/ModernInterface.lua` | `adapter.update`: early-return + startPanel.show() for lobby state |

`PromptEngine.lua`, `GameState.lua`, `PersistenceEngine.lua`, and all other panels: **no changes.**

---

## Edge Cases

| Scenario | Behaviour |
|---|---|
| Player disconnects during lobby state | `PlayerRemoving` skips save (`_isLobby=true`); on reconnect, DataStore has the old game-over save, which is loaded and shown as game-over; player clicks Restart again → lobby → firm name |
| ChooseStart double-fire during lobby | Second call: `existing.startChoice` is now set → blocked ✓ |
| Returning player (saved game) | DataStore load has `startChoice` set → never enters lobby path ✓ |
| Interface switch during lobby | `SetUIMode` still fires; state arrives; `startChoice==nil` → correct interface shows firm name ✓ |
