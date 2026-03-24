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
- Full-screen 40-column grid scaled to fill the screen (independent of the modern UI's 480px column)
- Mobile-friendly: virtual key buttons appear for touch players when single-key input is expected
- Placeholder composable glitch layer for future CRT effects (scan lines, phosphor glow)
- Zero changes to engine modules or test specs; zero changes to existing panel files (settings button is an independent element in ModernInterface, not added inside any panel)
- Live interface switching mid-session (no rejoin required)

---

## Architecture

### Adapter Contract

Both interfaces implement the same three-method contract:

```lua
adapter.update(state)     -- called on every StateUpdate from server
adapter.notify(message)   -- called on every Notify from server
adapter.destroy()         -- called when switching interfaces (cleanup)
```

`InterfacePicker` also implements this contract. Its `update` and `notify` methods are no-ops — the picker is only destroyed when `state.uiMode` becomes non-nil in a subsequent StateUpdate, at which point the bootstrapper calls `destroy()` and instantiates the real adapter.

### Bootstrapper (`init.client.lua` — replaced)

The existing `init.client.lua` is replaced with a ~30-line bootstrapper. It no longer knows about any specific panel. It tracks `currentMode` (string, initially `nil`) to detect interface switches. Responsibilities:

1. Connect to `Remotes.StateUpdate` and `Remotes.Notify`
2. On **every** `StateUpdate`:
   - If `type(state) ~= "table"` (server boolean sentinel during async DataStore load) → ignore entirely; do nothing. The bootstrapper never passes a non-table value to any adapter.
   - Determine whether to (re)instantiate an adapter:
     - **No adapter yet** (`currentMode == nil`): instantiate based on `state.uiMode`:
       - `nil` → instantiate `InterfacePicker`; set `currentMode = "picker"`
       - `"modern"` → instantiate `ModernInterface`; set `currentMode = "modern"`
       - `"apple2"` → instantiate `Apple2Interface`; set `currentMode = "apple2"`
     - **Picker active, mode now chosen** (`currentMode == "picker"` and `state.uiMode ~= nil`): call `adapter.destroy()` on the picker; instantiate the chosen interface; set `currentMode = state.uiMode`
     - **Live interface switch** (`currentMode` is `"modern"` or `"apple2"`, and `state.uiMode ~= currentMode`): call `adapter.destroy()`; instantiate the new adapter; set `currentMode = state.uiMode`
     - Otherwise: no instantiation change
   - Call `adapter.update(state)` on the current adapter
3. Wire `Notify` → call `adapter.notify(message)` on whatever adapter is current at time of event

This logic handles both new players (first StateUpdate has `uiMode == nil` → picker) and returning players (first StateUpdate has `uiMode` set from persisted save → adapter instantiated directly) uniformly.

### StartPanel Ownership

`StartPanel` (the "firm or ship" choice) is owned by **both interface adapters independently**:

- **`ModernInterface`**: Instantiates `StartPanel` as one of its managed panels. `startPanel.hide()` is called unconditionally on every `adapter.update(state)` call — the method is idempotent (it destroys the frame on first call; subsequent calls are no-ops since the frame is already gone).
- **`Apple2Interface`**: When `state.turnsElapsed == 1` and `state.destination == 0` (game not yet started), the PromptEngine enters a `StartChoice` scene that presents the firm/ship choice as sequential text prompts. On selection, `GameActions.chooseStart(choice)` fires.

`InterfacePicker` fires before the game is started, so it never needs to show StartPanel — that happens inside whichever adapter is instantiated after the mode is chosen.

---

## File Structure

### New Files

```
src/StarterGui/TaipanGui/
  GameActions.lua           -- shared Remote wrappers (imported by both interfaces)
  InterfacePicker.lua       -- first-time interface selection screen (adapter contract)
  ModernInterface.lua       -- adapter wrapping existing Panels/ unchanged
  Apple2Interface.lua       -- Apple II terminal controller (adapter contract)
  Apple2/
    Terminal.lua            -- bitmap font screen manager
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

All 13 existing panel files (settings access in the Modern UI is provided by a standalone button created in `ModernInterface.lua`, not by modifying any panel), all engine modules, all test specs, `Text/` font library.

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

`adapter.notify(message)` maps directly to `messagePanel.show(message)` — the existing MessagePanel exposes `show()` rather than `notify()`, and this single-line mapping lives inside ModernInterface.

The settings entry point is a standalone `TextButton` created by ModernInterface and parented directly to the Root frame (not inside any existing panel). It is positioned in the PortPanel region and made visible only when `not state.gameOver and state.combat == nil and state.shipOffer == nil`. Clicking it shows a sub-prompt (implemented as a small overlay Frame) offering `(M)odern / (A)pple II / (C)ancel`. On confirmation, fires `GameActions.setUIMode(newMode)`.

```lua
function ModernInterface.new(screenGui, actions)
  -- creates Root frame (480px wide column, black background)
  -- instantiates all 13 panels with actions.X callbacks
  -- creates standalone settings button (not inside any panel)
  -- returns { update(state), notify(message), destroy() }
  --   where notify(msg) calls messagePanel.show(msg)
  --   where update(state) calls startPanel.hide() unconditionally (idempotent)
end
```

### `InterfacePicker.lua`

Full-screen overlay (ZIndex 30) shown when `state.uiMode == nil`. Implements the three-method adapter contract: `update` and `notify` are no-ops; `destroy` removes the frame.

Presents two choices as both clickable buttons and keyboard shortcuts (M / A):

```
          TAIPAN!

  Choose your interface:

  [M] Modern        — touch-friendly panels
  [A] Apple II      — keyboard terminal, authentic style

  (You can change this later from the Settings option at port)
```

On selection, fires `GameActions.setUIMode(mode)`. The bootstrapper receives the next StateUpdate (with `state.uiMode` now set), detects the mode change from `"picker"`, calls `picker.destroy()`, and instantiates the chosen interface.

### `Apple2Interface.lua`

Orchestrates Terminal, PromptEngine, KeyInput, and GlitchLayer. Implements the three-method adapter contract.

**Internal state**: holds `lastState` (most recent server state table) and `localScene` (string or nil, set by player keypresses).

**`update(state)`**:
1. Sets `lastState = state`
2. Any server-driven scene (Combat, ShipOffers, WuSession, GameOver) clears `localScene` to nil — these override whatever sub-scene the player was in
3. Calls `PromptEngine.processState(state, localScene)` → returns `{lines, promptDef}`
4. Calls `Terminal.clear()` then calls `Terminal.print(line, color)` for each line
5. Calls `KeyInput.setPrompt(promptDef, lastState, actions)`

**Local scene transitions** (player presses B, S, W, K at AtPort):
- Apple2Interface calls `KeyInput.setLocalSceneCallback(function(scene) ... end)`
- When a scene-changing key is pressed (e.g., B), KeyInput calls this callback with `"buy"`
- The callback sets `localScene = "buy"`, then calls `PromptEngine.processState(lastState, "buy")` and re-renders Terminal and KeyInput without waiting for a StateUpdate

**`notify(message)`**: Splits message on `\n` and calls `Terminal.print(line, AMBER)` for each line, below the current display. Does not clear the screen. Does not change the active promptDef.

**`destroy()`**: Disconnects KeyInput listeners, calls `Terminal.destroy()` and `GlitchLayer.destroy()`.

### `Terminal.lua`

Manages the full-screen bitmap font display using the existing `Text` library.

**Container**: Call `Text.GetTextGUI(displayOrder)` (where `displayOrder` is e.g. 5, above TaipanGui's default). This returns a `ScreenGui` containing a `TextParent` frame with a 16:9 `UIAspectRatioConstraint` matching the library's 1920×1080 virtual coordinate space. The ScreenGui's parent is set to `LocalPlayer.PlayerGui`. All Text object `.Parent` properties are set to `textGui.TextParent`. A solid black `Frame` (full size, `BackgroundColor3 = Color3.new(0,0,0)`, `BackgroundTransparency = 0`, `ZIndex = 0`) is parented to `TextParent` as the terminal background.

**Grid layout using `TaipanStandardFont`**: The `TaipanStandardFont` glyphs have `xadvance = 16` and `height = 16` virtual pixels (from `FontData.lua`). At `TextSize = 3`:
- Each character occupies 48×48 virtual pixels
- 40 columns: 40 × 48 = 1920 virtual pixels (exactly fills virtual width)
- Row positions: row `n` (1-indexed) starts at Y = `(n - 1) * 48` virtual pixels
- At `TextSize = 3`, rows 1–22 fit within the 1080px virtual height (22 × 48 = 1056px). Row 23 starts at Y=1056 and extends to Y=1104, which is 24px beyond the virtual bottom; row 24 starts at Y=1104. Rows 23–24 will be clipped at the screen edge — this is acceptable (authentic CRT overscan behavior). The spec uses a logical 24-row model; the implementer should be aware that rows 23–24 may be partially off-screen and should reserve them for less critical content (e.g., the input line at row 24 may need to be placed at row 22 or 23 instead).

**Newline handling**: `Terminal.print(text, color)` splits `text` on `\n` and calls itself recursively for each segment. Callers may pass multi-line strings; single-line strings work as before.

**Row objects**: A fixed pool of 24 `Text.new("TaipanStandardFont", true)` objects. `automatic_update = true` connects each to `RunService.RenderStepped` internally. Each object's `.Parent` is set to `textGui.TextParent`, its `.Position` is set to `Vector2.new(0, (row-1)*48)`, and its `.TextSize` is set to `3`.

**API**:
- `print(text, color)` — splits on `\n`; appends each line to the buffer; if buffer is full (all 24 rows occupied), shifts rows 1–23 up one (row 1 discarded) and places the new line at row 24
- `clear()` — sets all 24 Text objects' `.Text` to `""` and resets the buffer
- `showInputLine(text)` — writes `text` to row 24 without shifting the buffer (dedicated input row)
- `setRowColor(row, color)` — sets `Text.TextColor3` on the specified row object
- `destroy()` — calls `:Destroy()` on each Text object (which disconnects RenderStepped) and destroys the ScreenGui

### `PromptEngine.lua`

Maps game state + local scene to output. Signature:

```lua
PromptEngine.processState(state, localScene) → { lines: string[], promptDef: table }
```

`localScene` is a string set by Apple2Interface based on player keypresses at AtPort (`"buy"`, `"sell"`, `"warehouse"`, `"bank"`). It is `nil` when no sub-scene is active or when a server-driven scene overrides.

**Scene determination** (evaluated in priority order; server-driven scenes override localScene):

| Priority | Scene | Condition |
|---|---|---|
| 1 | `GameOver` | `state.gameOver == true` |
| 2 | `Combat` | `state.combat ~= nil` |
| 3 | `ShipOffers` | `state.shipOffer ~= nil` |
| 4 | `WuSession` | `state.currentPort == HONG_KONG and state.inWuSession == true` |
| 5 | `BankSession` | `localScene == "bank"` |
| 6 | `WarehouseSession` | `localScene == "warehouse"` |
| 7 | `BuySell` | `localScene == "buy"` or `localScene == "sell"` |
| 8 | `StartChoice` | `state.turnsElapsed == 1 and state.destination == 0` |
| 9 | `AtPort` | default |

**Note on `WuSession`**: `state.inWuSession` is an ephemeral field — it is not persisted across reconnects, but it is reliably present in the live state table. The server sets `inWuSession = true` when the player arrives at Hong Kong and pushes state immediately, so the first StateUpdate after HK arrival will have `inWuSession == true`. Wu interaction in the Apple II interface is therefore automatic on HK arrival (same as original game), not player-initiated. The AtPort menu does NOT include a manual Wu entry point.

**Local scene flag lifecycle**:
- Set by Apple2Interface when the player presses B, S, W, or K at AtPort
- Cleared when: (a) a server-driven scene activates (priorities 1–4 in the table above), (b) the player presses C or Escape (cancel/back key shown in every sub-scene prompt), or (c) a server action succeeds (Apple2Interface clears `localScene` before calling `processState` with the new state)
- Each sub-scene shows an explicit Cancel key in its prompt hint

**`promptDef` structure**:

```lua
promptDef = {
  type   = "key",              -- "key" (single keypress) or "type" (typed + Enter)
  keys   = {"F", "R", "T"},   -- valid keys for "key" mode (uppercase single chars)
  label  = "(F)ight (R)un (T)hrow",  -- display hint shown at bottom of terminal
  onKey  = function(key, state, actions) ... end,
  -- For "type" mode:
  onType = function(text, state, actions) → string|nil end,
  --   Returns nil on success (Apple2Interface clears localScene, waits for StateUpdate)
  --   Returns an error string to re-display on terminal and re-prompt without scene change
  typePlaceholder = "amount (A=all): ",  -- prefix shown in input line
}
```

**Type mode input rules**:
- The "A" shorthand is supported: if submitted text is `"A"` or `"a"`, `onType` resolves it to the appropriate maximum quantity (same logic as the modern panels: all cash for repay, all cargo for sell, all hold space for buy, etc.) before calling `GameActions`
- On invalid input (non-numeric, negative, zero, exceeds valid range), `onType` returns an error string. Apple2Interface prints the error to Terminal and re-calls `KeyInput.setPrompt(promptDef, ...)` so the player is re-prompted without re-rendering the whole scene
- On success, `onType` returns nil; Apple2Interface clears the input line and `localScene`, and waits for the next StateUpdate to re-render

**AtPort menu example** (HK, all options shown):
```
HONG KONG                         Jan 1860
Cash: $400  Debt: $5,000  Bank: $0  Guns: 0
Hold: 60/60  Damage: 0%

Prices:
  Opium:   $1,234   Silk:    $456
  Arms:    $78      General: $9

(B)uy  (S)ell  (T)ravel  (W)arehouse
(K)Bank  (R)etire  (!)Settings  (Q)uit
```

*(Wu interaction activates automatically when arriving at HK — there is no manual Wu entry key in the AtPort menu.)*

**Combat menu example**:
```
BATTLE!!                        SW: 100%
Enemy ships: 5 remaining
[##########]  (5 ships shown)

(F)ight  (R)un  (T)hrow cargo overboard
```

**Settings sub-prompt** (accessible via `!` at AtPort only — not reachable from Combat, ShipOffers, WuSession, or GameOver):
```
Switch interface? (M)odern / (A)pple II / (C)ancel
```

### `KeyInput.lua`

Handles player input and calls back into Apple2Interface.

**Mobile detection**: Uses `UserInputService.TouchEnabled` (the standard Roblox idiom for detecting touch/mobile devices).

**`setPrompt(promptDef, state, actions)`**: Disconnects previous input listeners, destroys mobile virtual buttons if any, then activates the new mode.

**Key mode** (`promptDef.type == "key"`):
- Desktop: `UserInputService.InputBegan` → converts `input.KeyCode` to uppercase letter → checks against `promptDef.keys` → calls `promptDef.onKey(key, state, actions)`
- Mobile (`TouchEnabled == true`): renders a row of `TextButton`s at screen bottom (ZIndex 50, above Terminal), one per key in `promptDef.keys`, labeled with the key letter. Tapping fires the same `onKey` callback.

**Type mode** (`promptDef.type == "type"`):
- Desktop: captures `UserInputService.InputBegan` for printable characters; Backspace removes last character; Enter submits. Buffer shown live via `Terminal.showInputLine(promptDef.typePlaceholder .. buffer)`.
- Mobile: a hidden `TextBox` (size 0×0, off-screen) is focused to trigger Roblox's native on-screen keyboard. The `TextBox.Text` is mirrored to `Terminal.showInputLine()` each frame via a `RunService.RenderStepped` connection. `TextBox.FocusLost` with `enterPressed == true` submits the buffer.

### `GlitchLayer.lua`

Stub. Creates a transparent `Frame` covering the full screen, parented to the `TextParent` frame inside the Terminal's ScreenGui at ZIndex 100 (above all terminal content).

```lua
function GlitchLayer.new(terminalGui)
  -- terminalGui is the ScreenGui returned by Text.GetTextGUI()
  local frame = Instance.new("Frame")
  frame.Size = UDim2.fromScale(1, 1)
  frame.BackgroundTransparency = 1
  frame.ZIndex = 100
  frame.Visible = false
  frame.Parent = terminalGui.TextParent
  return {
    enable  = function() frame.Visible = true end,
    disable = function() frame.Visible = false end,
    destroy = function() frame:Destroy() end,
  }
end
```

Future implementation will add scan lines, phosphor bloom, and random pixel glitches as children of this frame without requiring changes to other modules.

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

Settings is reachable only from AtPort-equivalent scenes (not during Combat, ShipOffers, WuSession, or GameOver). The server `SetUIMode` handler guards with `if type(state) ~= "table" then return end` as all handlers do; no additional server-side guard is needed since the client never offers the settings option during those scenes.

- **Modern interface**: A standalone settings button created by ModernInterface, positioned in the PortPanel region, visible only when `not state.gameOver and state.combat == nil and state.shipOffer == nil`
- **Apple II interface**: `(!)Settings` key available only in the AtPort scene promptDef

Both present:
```
Switch interface? (M)odern / (A)pple II / (C)ancel
```

On confirmation, `GameActions.setUIMode(newMode)` fires. The bootstrapper detects `state.uiMode` changed (comparing to `currentMode`), calls `currentAdapter.destroy()`, and instantiates the new adapter. No rejoin required.

---

## Refactoring Summary

**Required refactoring** (to support the dual-interface architecture):
- `init.client.lua`: Replace with bootstrapper (all panel wiring moves to `ModernInterface.lua`)
- `Remotes.lua`: +1 Remote
- `GameState.lua`: +1 field
- `GameService.server.lua`: +1 handler

**Not required** (existing code is already clean enough):
- No panel changes (settings button is a standalone element in ModernInterface)
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
