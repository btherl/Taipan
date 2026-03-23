# Apple II Interface Design
**Date:** 2026-03-24
**Status:** Approved
**Scope:** Dual-interface system — existing modern panel UI + new Apple II–style keyboard terminal

---

## Overview

Add an authentic Apple II–style keyboard terminal interface to Taipan! as an alternative to the existing touch-friendly panel UI. Players choose their preferred interface once; the choice is persisted. Both interfaces connect to the same server-authoritative game logic with no server-side game changes beyond a single new field and one new Remote.

---

## Goals

- High-fidelity Apple II aesthetic: bitmap fonts, green phosphor on black, sequential text prompts, no simultaneous panels
- Full-screen 40×24 grid scaled to fill the screen (independent of the modern UI's 480px column)
- Mobile-friendly: virtual key buttons appear for touch players when single-key input is expected
- Placeholder composable glitch layer for future CRT effects (scan lines, phosphor glow)
- Zero changes to existing panel files, engine modules, or test specs
- Live interface switching mid-session (no rejoin required)

---

## Architecture

### Adapter Contract

Both interfaces implement the same four-method contract:

```lua
adapter.update(state)     -- called on every StateUpdate from server
adapter.notify(message)   -- called on every Notify from server
adapter.destroy()         -- called when switching interfaces (cleanup)
```

### Bootstrapper (`init.client.lua` — replaced)

The existing `init.client.lua` is replaced with a ~30-line bootstrapper. It no longer knows about any specific panel. Responsibilities:

1. Connect to `Remotes.StateUpdate` and `Remotes.Notify`
2. On first `StateUpdate`:
   - If `state.uiMode == nil` → instantiate `InterfacePicker`
   - If `state.uiMode == "modern"` → instantiate `ModernInterface`
   - If `state.uiMode == "apple2"` → instantiate `Apple2Interface`
3. Wire `StateUpdate` → `adapter.update(state)`
4. Wire `Notify` → `adapter.notify(message)`
5. On subsequent `StateUpdate`, if `state.uiMode` changed from current mode → call `adapter.destroy()` and instantiate the new adapter

---

## File Structure

### New Files

```
src/StarterGui/TaipanGui/
  GameActions.lua           -- shared Remote wrappers (imported by both interfaces)
  InterfacePicker.lua       -- first-time interface selection screen
  ModernInterface.lua       -- adapter wrapping existing Panels/ unchanged
  Apple2Interface.lua       -- Apple II terminal controller (adapter contract)
  Apple2/
    Terminal.lua            -- 24-line bitmap font screen manager
    PromptEngine.lua        -- state → scene → text lines + promptDef
    KeyInput.lua            -- keyboard + mobile virtual-key input handler
    GlitchLayer.lua         -- stub overlay (future CRT effects)
```

### Modified Files

| File | Change |
|---|---|
| `src/StarterGui/TaipanGui/init.client.lua` | Replace contents with ~30-line bootstrapper |
| `src/ReplicatedStorage/Remotes.lua` | +1 RemoteEvent: `SetUIMode` |
| `src/ReplicatedStorage/shared/GameState.lua` | +1 field: `uiMode = nil` in `newGame()` |
| `src/ServerScriptService/GameService.server.lua` | +1 handler for `SetUIMode` (~8 lines) |

### Untouched Files

All 13 existing panel files, all engine modules (`PriceEngine`, `TravelEngine`, `FinanceEngine`, `EventEngine`, `CombatEngine`, `ProgressionEngine`, `PersistenceEngine`, `Validators`, `Constants`, `GameState` internals), all test specs, `Text/` font library.

---

## Module Designs

### `GameActions.lua`

A plain table of functions — one per server action. Both interfaces import this; no interface ever calls `Remotes` directly.

```lua
local Remotes = require(ReplicatedStorage.Remotes)
return {
  chooseStart    = function(choice) Remotes.ChooseStart:FireServer(choice) end,
  buyGoods       = function(g, q)   Remotes.BuyGoods:FireServer(g, q) end,
  sellGoods      = function(g, q)   Remotes.SellGoods:FireServer(g, q) end,
  travelTo       = function(dest)   Remotes.TravelTo:FireServer(dest) end,
  endTurn        = function()       Remotes.EndTurn:FireServer() end,
  wuRepay        = function(amt)    Remotes.WuRepay:FireServer(amt) end,
  wuBorrow       = function(amt)    Remotes.WuBorrow:FireServer(amt) end,
  leaveWu        = function()       Remotes.LeaveWu:FireServer() end,
  buyLiYuen      = function()       Remotes.BuyLiYuenProtection:FireServer() end,
  bankDeposit    = function(amt)    Remotes.BankDeposit:FireServer(amt) end,
  bankWithdraw   = function(amt)    Remotes.BankWithdraw:FireServer(amt) end,
  transferTo     = function(g, q)   Remotes.TransferToWarehouse:FireServer(g, q) end,
  transferFrom   = function(g, q)   Remotes.TransferFromWarehouse:FireServer(g, q) end,
  combatFight    = function()       Remotes.CombatFight:FireServer() end,
  combatRun      = function()       Remotes.CombatRun:FireServer() end,
  combatThrow    = function(g, q)   Remotes.CombatThrow:FireServer(g, q) end,
  shipRepair     = function(amt)    Remotes.ShipRepair:FireServer(amt) end,
  acceptUpgrade  = function()       Remotes.AcceptUpgrade:FireServer() end,
  declineUpgrade = function()       Remotes.DeclineUpgrade:FireServer() end,
  acceptGun      = function()       Remotes.AcceptGun:FireServer() end,
  declineGun     = function()       Remotes.DeclineGun:FireServer() end,
  shipPanelDone  = function()       Remotes.ShipPanelDone:FireServer() end,
  retire         = function()       Remotes.Retire:FireServer() end,
  quitGame       = function()       Remotes.QuitGame:FireServer() end,
  restartGame    = function()       Remotes.RestartGame:FireServer() end,
  setUIMode      = function(mode)   Remotes.SetUIMode:FireServer(mode) end,
  requestState   = function()       Remotes.RequestStateUpdate:FireServer() end,
}
```

### `ModernInterface.lua`

A thin adapter wrapping all 13 existing panels. Panels are instantiated exactly as in the current `init.client.lua`, with `GameActions` functions passed as callbacks. The `destroy()` method destroys the Root frame, cleaning up all panels.

```lua
function ModernInterface.new(screenGui, actions)
  -- creates Root frame (480px wide column)
  -- instantiates all 13 panels with actions.X callbacks
  -- adds settings button to PortPanel triggering actions.setUIMode
  -- returns { update(state), notify(message), destroy() }
end
```

### `InterfacePicker.lua`

Full-screen overlay (ZIndex 30) shown when `state.uiMode == nil`. Presents two choices as both clickable buttons and keyboard shortcuts:

```
          TAIPAN!

  Choose your interface:

  [M] Modern        — touch-friendly panels
  [A] Apple II      — keyboard terminal, authentic style

  (You can change this later from the Settings option at port)
```

On selection, fires `GameActions.setUIMode(mode)`. The bootstrapper receives the updated state and instantiates the chosen interface.

### `Apple2Interface.lua`

Orchestrates Terminal, PromptEngine, KeyInput, and GlitchLayer. On `update(state)`, calls `PromptEngine.processState(state)` which returns `{lines, promptDef}`, prints lines to Terminal, and passes promptDef to KeyInput. On `notify(message)`, prints the message to Terminal in amber. Exposes the standard adapter contract.

### `Terminal.lua`

Manages the 24-line full-screen text display.

- **Rendering**: Fixed pool of 24 `Text.new("TaipanStandardFont")` objects (one per row). The 40×24 grid fills the full screen via `UIAspectRatioConstraint`. Background is solid black (`Color3.fromRGB(0, 0, 0)`).
- **API**:
  - `print(text, color)` — appends a line to the buffer; scrolls all rows up when full
  - `clear()` — wipes all 24 lines
  - `showInputLine(text)` — updates row 24 (the input line) with typed-so-far characters
  - `setRowColor(row, color)` — recolor a specific row

### `PromptEngine.lua`

Maps game state to scenes. On each `processState(state)` call, compares to previous state, determines the current scene, and returns `{lines, promptDef}`.

**Scene determination** (evaluated in priority order):

| Scene | Condition |
|---|---|
| `GameOver` | `state.gameOver == true` |
| `Combat` | `state.combat ~= nil` |
| `ShipOffers` | `state.shipOffer ~= nil` |
| `WuSession` | `state.currentPort == HONG_KONG and state.inWuSession` |
| `BankSession` | player pressed K at port (local scene flag) |
| `WarehouseSession` | player pressed W at port (local scene flag) |
| `BuySell` | player pressed B or S at port (local scene flag) |
| `AtPort` | default |

**`promptDef` structure**:

```lua
promptDef = {
  type   = "key",              -- "key" (single keypress) or "type" (typed + Enter)
  keys   = {"F", "R", "T"},   -- valid keys for "key" mode
  label  = "(F)ight (R)un (T)hrow",  -- display hint shown on terminal
  onKey  = function(key, state, actions) ... end,  -- fires GameActions
  onType = function(text, state, actions) ... end, -- "type" mode only
}
```

Sub-scenes (BuySell, Warehouse, Wu, Bank) are local client state — they don't require a server round-trip to enter. The server is only contacted when an action is taken.

**AtPort menu** (example output):
```
HONG KONG                         Jan 1860
Cash: $400  Debt: $5,000  Bank: $0  Guns: 0
Hold: 60/60  Damage: 0%

Prices:
  Opium:   $1,234   Silk:    $456
  Arms:    $78      General: $9

(B)uy  (S)ell  (T)ravel  (W)arehouse
(K)Bank  (E)Wu  (!)Settings  (Q)uit
```

**Combat menu** (example output):
```
BATTLE!!                        SW: 100%
Enemy ships: 5 remaining
[##########]  (5 ships shown)

(F)ight  (R)un  (T)hrow cargo overboard
```

### `KeyInput.lua`

Handles player input and calls back into PromptEngine.

**Key mode** (`promptDef.type == "key"`):
- `UserInputService.InputBegan` → if `input.KeyCode` matches a key in `promptDef.keys` → calls `promptDef.onKey(key, state, actions)`
- Mobile: renders a row of `TextButton`s at screen bottom, one per key in `promptDef.keys`. Tapping fires the same callback.

**Type mode** (`promptDef.type == "type"`):
- Captures keystrokes into a local string buffer
- Backspace removes last character
- Enter submits: calls `promptDef.onType(buffer, state, actions)` and clears buffer
- Buffer is shown live via `Terminal.showInputLine()`
- Mobile: Roblox's native on-screen keyboard appears automatically via a hidden `TextBox`

**Mobile detection**: `GuiService:IsTenFootInterface()` or screen width below a threshold (e.g., 768px).

### `GlitchLayer.lua`

Stub. Creates a transparent `Frame` covering the full screen at ZIndex 100.

```lua
function GlitchLayer.new(screenGui)
  local frame = Instance.new("Frame")
  frame.Size = UDim2.new(1, 0, 1, 0)
  frame.BackgroundTransparency = 1
  frame.ZIndex = 100
  frame.Parent = screenGui
  return {
    enable  = function() frame.Visible = true end,
    disable = function() frame.Visible = false end,
    destroy = function() frame:Destroy() end,
  }
end
```

Future implementation will add scan lines, phosphor bloom, random pixel glitches as children of this frame.

---

## Server Changes

### `Remotes.lua`
Add one new `RemoteEvent`:
```lua
SetUIMode = Instance.new("RemoteEvent"),
```

### `GameState.lua`
Add one field to `newGame()`:
```lua
uiMode = nil,   -- nil = not yet chosen; "modern" or "apple2" once set
```
`uiMode` is canonical (persisted). It survives reconnects and save/load cycles.

### `GameService.server.lua`
Add one handler (~8 lines):
```lua
Remotes.SetUIMode.OnServerEvent:Connect(function(player, mode)
  local state = playerStates[player]
  if type(state) ~= "table" then return end
  if mode ~= "modern" and mode ~= "apple2" then return end
  state.uiMode = mode
  savePlayer(player, state)
  pushState(player)
end)
```

`PersistenceEngine` serializes `uiMode` automatically — no changes needed there.

---

## Interface Switching

The settings entry point differs by interface:

- **Modern interface**: A small settings button added to PortPanel (visible only when not in combat or game-over)
- **Apple II interface**: `(!)Settings` key available in the AtPort menu

Both show a sub-prompt:
```
Switch interface? (M)odern / (A)pple II / (C)ancel
```

On confirmation, `GameActions.setUIMode(newMode)` fires. The bootstrapper detects the `uiMode` change in the next `StateUpdate`, calls `currentAdapter.destroy()`, and instantiates the new adapter. No rejoin required.

---

## Refactoring Summary

**Required refactoring** (to support the dual-interface architecture):
- `init.client.lua`: Replace with bootstrapper (all panel wiring moves to `ModernInterface.lua`)
- `Remotes.lua`: +1 Remote
- `GameState.lua`: +1 field
- `GameService.server.lua`: +1 handler

**Not required** (existing code is already clean enough):
- No panel changes
- No engine module changes
- No ViewModel/MVC extraction
- No test spec changes

The existing panel `.update(state)` contract and callback pattern are sufficient as-is. The only structural issue in the current code is that `init.client.lua` conflates bootstrapping with panel-wiring — extracting that wiring into `ModernInterface.lua` resolves it cleanly.

---

## Out of Scope

- CRT glitch effects (GlitchLayer stub only)
- Sound effects (Apple II beeps)
- Animated text scrolling / typewriter effect (can be added inside Terminal.lua later without interface changes)
- Accessibility features beyond mobile virtual keys
