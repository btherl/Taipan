# Design: Restart Returns to Firm Name Screen

**Date:** 2026-03-30
**Status:** Approved

## Problem

After any game ending (ship sunk, quit, or retired), the RESTART button currently creates a new game using the previous `startChoice` and skips the firm name screen. The player has no opportunity to rename their firm or change their start type (cash vs guns).

## Goal

After any game-over (sunk, quit, or retired), both the Apple II and Modern UI return to the firm name screen. The player re-enters (or keeps) a firm name and re-picks their start type before the new game begins.

**Note on "fresh launch" similarity:** The firm name text box retains whatever the player typed in the previous game (it is not cleared on restart). This is an intentional UX choice — returning to retype the same name is annoying. The behaviour differs from a true first launch (where the box is empty) but is preferred.

## Approach

**Option A — Server sends a "lobby" state.** `RestartGame` pushes a minimal pre-game state (`startChoice=nil`) to the client. Existing client routing already treats `startChoice==nil` as "show firm name screen." The only new client work is making `StartPanel` re-showable (Modern UI) and resetting `localScene` on lobby arrival (Apple II).

Chosen because it keeps the server-authoritative, state-driven pattern intact. No new remotes, no imperative client-side resets.

---

## Design

### 1. Server — `GameService.server.lua`

#### RestartGame handler

Replaces the current handler (which built a full new game from `prevStartChoice`). The new handler fires a minimal **lobby state** directly to the client, then **sets `playerStates[player] = nil`**. This has two effects:

- All existing per-handler guards (`if type(state) ~= "table" then return end`) already reject `nil`, so no handler (BuyGoods, TravelTo, SetUIMode, etc.) can act on a stale or incomplete state. No handler changes needed.
- `playerStates[player] = nil` means `PlayerRemoving` skips the DataStore save (its guard is `if type(state) == "table" then savePlayer(...) end`), so the lobby is never persisted.

```lua
Remotes.RestartGame.OnServerEvent:Connect(function(player)
  local state = playerStates[player]
  if type(state) ~= "table" or not state.gameOver then return end
  local lobbyState = {
    startChoice  = nil,
    gameOver     = false,
    turnsElapsed = 1,
    destination  = 0,
    uiMode       = state.uiMode,
    seenTutorial = state.seenTutorial,
  }
  -- Push the lobby state directly (bypasses pushState's table guard),
  -- then nil the slot so all existing handler guards block correctly.
  Remotes.StateUpdate:FireClient(player, lobbyState)
  playerStates[player] = nil
end)
```

#### ChooseStart guard

Changed from "block if any truthy value in slot" to "block if a real game is in progress":

```lua
local existing = playerStates[player]
if type(existing) == "table" and existing.startChoice ~= nil then return end
-- nil → new player or post-restart → allowed through
```

This lets `ChooseStart` create a fresh game after restart (`playerStates[player]` is nil). The rest of the handler is unchanged.

The original guard `if playerStates[player] then return end` blocked any truthy value. This project does not use a boolean sentinel in `playerStates` (no `= true` is set before the DataStore load in `PlayerAdded`), so the guard simplification is safe. If a non-table truthy value were ever placed in the slot (e.g. a future boolean sentinel), the new guard would fall through and allow `ChooseStart` to run; implementers should be aware of this if sentinel usage is ever added.

**Note on PlayerAdded race:** The `PlayerAdded` handler runs a `task.spawn` DataStore load with no boolean sentinel — `playerStates[player]` is nil during the async window. This race pre-existed the current change (the original guard `if playerStates[player] then return end` also falls through when the slot is nil). The risk (a returning player fires ChooseStart during the ~1-second load window) is accepted as-is; the InterfacePicker → firm name screen sequence makes this window practically unreachable.

**Note on `SetUIMode` during lobby:** If the player fires `SetUIMode` between the game ending and clicking RESTART, `pendingModes[player]` is updated but the old `state.uiMode` is snapshotted into `lobbyState`. The pushed lobby state may carry a slightly stale `uiMode`, meaning the firm name screen itself could render in the previous interface mode. This is accepted as-is (very narrow race, one frame of wrong mode at most); `ChooseStart` consumes `pendingModes[player]` when building the real game state, so the correct mode is applied for all gameplay.

The two lines `Remotes.StateUpdate:FireClient(player, lobbyState)` and `playerStates[player] = nil` execute sequentially in a single Roblox event handling coroutine. Roblox's single-threaded event model means no other handler coroutine can interleave between them; `FireClient` queues the message to the client but does not yield or allow other server events to run.

---

### 2. Apple II — `Apple2Interface.lua`

One addition to `adapter.update`: reset `localScene` to nil when a lobby state arrives, so any lingering local scene from the previous game does not block the firm name scene.

The lobby state satisfies none of the `SERVER_SCENES` checks (gameOver=false, combat=nil, shipOffer=nil, inWuSession=false), so `isServerDriven` returns false and `localScene` is not reset by the existing code. The new branch handles this:

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

The lobby state satisfies all three conditions (`turnsElapsed=1, destination=0`).

---

### 3. Modern UI — `StartPanel.lua` + `ModernInterface.lua`

#### StartPanel.lua

Change `panel.hide()` from destroying the frame to hiding it, and add `panel.show()`. The `show()` method must also reset the `chosen` flag and restore button appearance, so the panel is fully interactive again after a restart.

Define the default button colour as a local constant shared between the constructor and `show()`, to prevent silent drift:

```lua
local BUTTON_DEFAULT_COLOR = Color3.fromRGB(20, 20, 20)  -- add near top of StartPanel.new

function panel.hide()
  frame.Visible = false
end

function panel.show()
  chosen = false
  cashBtn.Active = true
  gunsBtn.Active = true
  cashBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
  gunsBtn.BackgroundColor3 = BUTTON_DEFAULT_COLOR
  prompt.Text = "Elder Brother Wu says:\n\"Do you have a firm, or a ship?\""
  frame.Visible = true
end
```

The constructor must also use `BUTTON_DEFAULT_COLOR` for `cashBtn.BackgroundColor3` and `gunsBtn.BackgroundColor3`. `show()` is safe to call on a panel that has never been hidden (buttons were never clicked, `chosen` is already false — the resets are idempotent). Both `hide()` and `show()` are idempotent. The name text box retains its value between cycles (intentional — see Goal).

`StartPanel` is constructed with `frame.Visible = true`. The `hide()` change (Visible=false instead of Destroy) is safe for all call paths:
- **New player first launch:** StartPanel visible from construction → player picks start → `adapter.update(state)` with `startChoice` set → `startPanel.hide()` → Visible=false ✓
- **Restart flow:** lobby state arrives → `startPanel.show()` (already may be visible, idempotent) ✓
- **Returning player (saved game):** first `adapter.update` has `startChoice` set → `startPanel.hide()` → Visible=false ✓

#### ModernInterface.lua

In `adapter.update`, detect the lobby state and show `StartPanel` instead of updating game panels. Also clean up the settings overlay if it is open (it would otherwise linger behind the StartPanel):

```lua
function adapter.update(state)
  -- Lobby state: startChoice is nil (a real game always has startChoice set).
  -- `not state.gameOver` is a defensive belt-and-suspenders check; in practice
  -- gameOver states always have startChoice set, so this branch is only reached
  -- via a genuine lobby state.
  if state.startChoice == nil and not state.gameOver then
    if settingsOverlay then
      settingsOverlay:Destroy()
      settingsOverlay = nil
    end
    settingsBtn.Visible = false
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
Player clicks RESTART (any ending: sunk / quit / retired)
  → actions.restartGame()
  → server RestartGame: fires lobbyState directly to client, sets playerStates[player] = nil

  Apple II path:
    adapter.update(lobbyState)
    → startChoice == nil → localScene = nil
    → render → PromptEngine: startChoice==nil → sceneFirmName ✓

  Modern path:
    adapter.update(lobbyState)
    → startChoice == nil → startPanel.show(), return ✓

Player enters firm name, picks start (firm name screen → start choice screen)
  → StartPanel.onChoose(choice, firmName) [Modern] or sceneFirmName.onType + sceneStartChoice.onKey [Apple II]
  → actions.setFirmName(firmName) ALWAYS called first with whatever is in the name box
    (even if empty — this clears any stale pendingFirmName from a previous game)
  → actions.chooseStart(choice) fires ChooseStart:FireServer(choice, pendingFirmName)
  → server ChooseStart: playerStates[player] is nil → allowed
  → creates real game state (GameState.newGame with firmName) → pushState
  → normal game begins ✓
```

---

## Files Changed

| File | Change |
|---|---|
| `src/ServerScriptService/GameService.server.lua` | RestartGame handler (lobby push + nil slot); ChooseStart guard |
| `src/StarterGui/TaipanGui/Apple2Interface.lua` | `adapter.update`: reset localScene when `startChoice == nil` |
| `src/StarterGui/TaipanGui/Panels/StartPanel.lua` | `panel.hide()` → Visible=false; add `panel.show()` with `chosen` reset |
| `src/StarterGui/TaipanGui/ModernInterface.lua` | `adapter.update`: early-return + startPanel.show() + overlay cleanup |

`PromptEngine.lua`, `GameState.lua`, `PersistenceEngine.lua`, and all other panels: **no changes.**

---

## Edge Cases

| Scenario | Behaviour |
|---|---|
| Player disconnects during lobby (playerStates nil) | `PlayerRemoving` guard fails → no save. DataStore unchanged. On reconnect, three sub-cases: **(a)** Last save was mid-game (player never disconnected during game-over) → player resumes that mid-game turn. **(b)** Player had previously disconnected while viewing the game-over screen (game-over table was saved by that earlier disconnect) → game-over state loads → player sees game-over again and can restart. **(c)** No prior save at all (first-ever game) → DataStore returns nil → no StateUpdate pushed → client shows InterfacePicker as a fresh player ✓ |
| ChooseStart double-fire during lobby | First call sets real state with startChoice; second call: `existing.startChoice ~= nil` → blocked ✓ |
| Returning player (saved game) | DataStore load has `startChoice` set → `ChooseStart` guard blocks; never enters lobby path ✓ |
| SetUIMode during lobby (nil slot) | Handler guard `type(state) ~= "table"` returns early; `pendingModes[player]` is set. The existing `ChooseStart` handler already consumes `pendingModes[player]` when building the real game state, so the correct uiMode is applied ✓ |
| BuyGoods / TravelTo / any other handler during lobby | Guard `type(state) ~= "table"` returns early (slot is nil) ✓ |
| Settings overlay open when game ends and player restarts | `adapter.update` lobby branch destroys overlay before showing StartPanel ✓ |
