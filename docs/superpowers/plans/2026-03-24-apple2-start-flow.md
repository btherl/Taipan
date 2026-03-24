# Apple II Start Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New players choose interface then see the appropriate start choice screen; returning players are taken straight to their saved state using their saved interface.

**Architecture:** Server loads saved state immediately on `PlayerAdded` — if found, `pushState` fires and the client (still showing InterfacePicker) transitions straight to the game. New players get nothing from `PlayerAdded`; they pick interface via `InterfacePicker`'s new `onPicked` callback, which creates the adapter immediately and (for Apple II) shows `sceneStartChoice` before `ChooseStart` fires. A `pendingModes` server table bridges the gap between `SetUIMode` and the moment `ChooseStart` creates new-game state.

**Tech Stack:** Luau (Roblox), MCP Studio tools for live injection. No unit tests (all changed files are Roblox UI/server scripts — not pure-logic modules in `shared/`). Verification is manual via Studio Play mode.

---

## Files Changed

| File | Change |
|------|--------|
| `src/ServerScriptService/GameService.server.lua` | Add `pendingModes`; early load in `PlayerAdded`; update `SetUIMode`, `ChooseStart`, `PlayerRemoving` |
| `src/StarterGui/TaipanGui/InterfacePicker.lua` | Remove Phase 2; add `onPicked` callback; `update()` → no-op |
| `src/StarterGui/TaipanGui/init.client.lua` | Pass `onPicked` to picker; immediate adapter creation on pick |
| `src/StarterGui/TaipanGui/Apple2Interface.lua` | Defensive `state or {}` in `render()` |
| `src/StarterGui/TaipanGui/Apple2/PromptEngine.lua` | Update stale comment at lines 660–661 |

---

## MCP Injection Reminder

Every disk edit must also be injected into Studio via MCP. After each file edit:
- Use `mcp__Roblox_Studio__script_read` to read the Studio-side version first (content may differ from disk — Studio strips some comments)
- Use `mcp__Roblox_Studio__multi_edit` to apply the change to Studio

Stop Play mode before injecting (`mcp__Roblox_Studio__start_stop_play` with `is_start=false`).

---

## Task 1: Server — add `pendingModes` table and early load in `PlayerAdded`

**Files:**
- Modify: `src/ServerScriptService/GameService.server.lua`

### Context

`playerStates` is declared at line 27. `PlayerAdded` is at line 645. `loadPlayer` is defined at line 37 — in Studio it always returns `nil` (DataStore bypassed), so the early-load path is a no-op in Studio but works in production.

The `playerStates[player] == nil` guard in the early load prevents overriding state that `ChooseStart` may have already set (theoretical race: human clicks through picker faster than DataStore responds — essentially impossible, but defensive).

- [ ] **Step 1: Edit `GameService.server.lua` on disk — add `pendingModes` after `playerStates`**

Find line 27:
```lua
local playerStates: {[Player]: any} = {}
```
Add after it:
```lua
local pendingModes: {[Player]: string} = {}
```

- [ ] **Step 2: Edit `GameService.server.lua` on disk — add early load inside `PlayerAdded`**

Find the existing `PlayerAdded` handler (line 645):
```lua
Players.PlayerAdded:Connect(function(player)
  task.defer(function()
    local StarterGui = game:GetService("StarterGui")
    for _, gui in ipairs(StarterGui:GetChildren()) do
      local clone = gui:Clone()
      clone.Parent = player.PlayerGui
    end
  end)
end)
```
Replace with:
```lua
Players.PlayerAdded:Connect(function(player)
  task.defer(function()
    local StarterGui = game:GetService("StarterGui")
    for _, gui in ipairs(StarterGui:GetChildren()) do
      local clone = gui:Clone()
      clone.Parent = player.PlayerGui
    end
    -- Returning players: load save and push state immediately.
    -- Client (showing InterfacePicker) receives StateUpdate with uiMode set
    -- and transitions straight to the saved game — no picker interaction needed.
    -- Guard: only apply if ChooseStart hasn't already claimed the slot.
    task.spawn(function()
      local loaded = loadPlayer(player)
      if loaded and playerStates[player] == nil then
        playerStates[player] = loaded
        pushState(player)
      end
    end)
  end)
end)
```

- [ ] **Step 3: Inject both changes into Studio via MCP**

Use `mcp__Roblox_Studio__script_read` on `GameService` to get Studio's current content, then `mcp__Roblox_Studio__multi_edit` to apply both edits.

- [ ] **Step 4: Commit**

```bash
git add src/ServerScriptService/GameService.server.lua
git commit -m "feat: early DataStore load in PlayerAdded for returning players"
```

---

## Task 2: Server — update `SetUIMode` and `PlayerRemoving` handlers

**Files:**
- Modify: `src/ServerScriptService/GameService.server.lua`

### Context

`SetUIMode` is at line 667. Currently it returns early if state doesn't exist (`type(state) ~= "table"`). The new design stores the mode in `pendingModes` first, then applies it to state only if state already exists (e.g. live interface switch from settings mid-game).

`PlayerRemoving` is at line 656 and must clear `pendingModes[player]` to avoid memory leak.

- [ ] **Step 1: Edit `SetUIMode` handler on disk**

Find (line 667):
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
Replace with:
```lua
Remotes.SetUIMode.OnServerEvent:Connect(function(player, mode)
  if mode ~= "modern" and mode ~= "apple2" then return end
  pendingModes[player] = mode
  local state = playerStates[player]
  if type(state) == "table" then
    state.uiMode = mode
    savePlayer(player, state)
    pushState(player)
  end
end)
```

- [ ] **Step 2: Edit `PlayerRemoving` handler on disk — add pendingModes cleanup**

Find (line 656):
```lua
Players.PlayerRemoving:Connect(function(player)
  local state = playerStates[player]
  if type(state) == "table" then
    savePlayer(player, state)  -- save before removing from map
  end
  playerStates[player] = nil
end)
```
Replace with:
```lua
Players.PlayerRemoving:Connect(function(player)
  local state = playerStates[player]
  if type(state) == "table" then
    savePlayer(player, state)  -- save before removing from map
  end
  playerStates[player] = nil
  pendingModes[player] = nil
end)
```

- [ ] **Step 3: Inject into Studio via MCP**

- [ ] **Step 4: Commit**

```bash
git add src/ServerScriptService/GameService.server.lua
git commit -m "feat: pendingModes in SetUIMode; cleanup in PlayerRemoving"
```

---

## Task 3: Server — update `ChooseStart` handler

**Files:**
- Modify: `src/ServerScriptService/GameService.server.lua`

### Context

`ChooseStart` is at line 59. The loaded-save branch (`if loaded then ... return end`) is removed — DataStore loading for returning players now happens in `PlayerAdded`. `ChooseStart` only creates new-game state now. Apply `pendingModes` before `pushState` so the new game gets the right `uiMode`.

Note: the existing sentinel guard (`if playerStates[player] then return end`) remains. For returning players whose state was set by `PlayerAdded`, any accidental `ChooseStart` fires are silently dropped.

- [ ] **Step 1: Edit `ChooseStart` handler on disk**

Find (lines 59–85):
```lua
Remotes.ChooseStart.OnServerEvent:Connect(function(player, startChoice)
  if startChoice ~= "cash" and startChoice ~= "guns" then startChoice = "cash" end
  if playerStates[player] then return end           -- already initialised (or sentinel)
  playerStates[player] = true                       -- sentinel: claim slot before async
  -- RequestStateUpdate calling pushState during this window silently no-ops (type guard).

  local loaded = loadPlayer(player)                 -- yields on DataStore call
  if loaded then
    -- Works for both resumed games (gameOver=false) and game-over saves (gameOver=true).
    -- Client renders whichever screen is appropriate from the pushed state.
    playerStates[player] = loaded
    pushState(player)
    return
  end

  -- No save found: start a fresh game
  local state = GameState.newGame(startChoice)
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2]
    - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  -- state.seenTutorial is already false (set by GameState.newGame)
  state.pendingTutorial = true  -- fires tutorial on first HK arrival; not in newGame
  playerStates[player] = state
  pushState(player)
end)
```
Replace with:
```lua
Remotes.ChooseStart.OnServerEvent:Connect(function(player, startChoice)
  if startChoice ~= "cash" and startChoice ~= "guns" then startChoice = "cash" end
  if playerStates[player] then return end           -- already initialised (or sentinel)

  -- New player: start a fresh game
  local state = GameState.newGame(startChoice)
  state.currentPrices = PriceEngine.calculatePrices(state.basePrices, state.currentPort)
  state.holdSpace = state.shipCapacity
    - state.shipCargo[1] - state.shipCargo[2]
    - state.shipCargo[3] - state.shipCargo[4]
    - state.guns * 10
  -- state.seenTutorial is already false (set by GameState.newGame)
  state.pendingTutorial = true  -- fires tutorial on first HK arrival; not in newGame
  if pendingModes[player] then
    state.uiMode = pendingModes[player]
    pendingModes[player] = nil
  end
  playerStates[player] = state
  pushState(player)
end)
```

- [ ] **Step 2: Inject into Studio via MCP**

- [ ] **Step 3: Verify in Studio (Play mode)**

Start Play. You should reach the InterfacePicker. Pick Apple II (press A). The terminal should render "Do you have a firm, or a ship?". Press F or S. Port scene should appear.

Pick Modern. StartPanel should appear. Click Firm or Ship. Port panels should appear.

- [ ] **Step 4: Commit**

```bash
git add src/ServerScriptService/GameService.server.lua
git commit -m "feat: ChooseStart only creates new games; pendingMode applied to state"
```

---

## Task 4: Update `PromptEngine.lua` comment

**Files:**
- Modify: `src/StarterGui/TaipanGui/Apple2/PromptEngine.lua`

### Context

Lines 660–661 have a comment that was accurate before this feature but is now wrong. The comment says InterfacePicker ensures `startChoice` is always set on arrival. Under the new design, `Apple2Interface.update({})` is called with an empty state — `startChoice` is intentionally nil. Update the comment only; no logic changes.

- [ ] **Step 1: Edit `PromptEngine.lua` on disk**

Find (lines 660–662):
```lua
  -- StartChoice: only when startChoice not yet made (InterfacePicker handles this
  -- before Apple2Interface is created, so state.startChoice is always set on arrival)
  if state.startChoice == nil and (state.turnsElapsed or 1) == 1 and (state.destination or 0) == 0 then
```
Replace the two comment lines:
```lua
  -- StartChoice: fires when startChoice is nil (pre-choice), including the initial
  -- update({}) call from the bootstrapper before ChooseStart has been sent.
  if state.startChoice == nil and (state.turnsElapsed or 1) == 1 and (state.destination or 0) == 0 then
```

- [ ] **Step 2: Inject into Studio via MCP**

- [ ] **Step 3: Commit**

```bash
git add src/StarterGui/TaipanGui/Apple2/PromptEngine.lua
git commit -m "docs: update stale sceneStartChoice comment in PromptEngine"
```

---

## Task 5: Update `Apple2Interface.lua` — defensive `state or {}`

**Files:**
- Modify: `src/StarterGui/TaipanGui/Apple2Interface.lua`

### Context

`render()` at line 48 passes `state` directly to `PromptEngine.processState`. In the new flow `update({})` is always called (not `update(nil)`), so `state` is `{}` not nil. The `or {}` is a defensive guard against future nil calls.

- [ ] **Step 1: Edit `Apple2Interface.lua` on disk**

Find line 48:
```lua
    local lines, promptDef = PromptEngine.processState(state, scene, actions,
```
Replace with:
```lua
    local lines, promptDef = PromptEngine.processState(state or {}, scene, actions,
```

- [ ] **Step 2: Inject into Studio via MCP**

- [ ] **Step 3: Commit**

```bash
git add src/StarterGui/TaipanGui/Apple2Interface.lua
git commit -m "fix: defensive state or {} in Apple2Interface render"
```

---

## Task 6: Rewrite `InterfacePicker.lua` — Phase 1 only with `onPicked` callback

**Files:**
- Modify: `src/StarterGui/TaipanGui/InterfacePicker.lua`

### Context

Current: two phases. Phase 1 = interface choice (sets `pendingMode`). Phase 2 = cash/guns choice (fires `chooseStart`). `update()` fires `setUIMode(pendingMode)`.

New: Phase 1 only. `onPicked(mode)` callback (third constructor arg) is called when the player picks. `update()` is a no-op. The bootstrapper handles everything after the pick.

Key: `chosen` guard remains to prevent double-fire on rapid clicks.

- [ ] **Step 1: Rewrite `InterfacePicker.lua` on disk**

Replace the entire file contents with:
```lua
-- InterfacePicker.lua
-- Phase 1 only: shows interface style choice (Modern / Apple II).
-- Calls onPicked(mode) immediately when player selects.
-- The bootstrapper (init.client.lua) creates the correct adapter and handles the rest.
local UserInputService = game:GetService("UserInputService")

local AMBER = Color3.fromRGB(200, 180, 80)
local GREEN = Color3.fromRGB(140, 200, 80)
local DIM   = Color3.fromRGB(120, 120, 120)

local InterfacePicker = {}

function InterfacePicker.new(screenGui, _actions, onPicked)
  local frame = Instance.new("Frame")
  frame.Name = "InterfacePicker"
  frame.Size = UDim2.new(1, 0, 1, 0)
  frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  frame.BorderSizePixel = 0
  frame.ZIndex = 30
  frame.Parent = screenGui

  local conn   = nil
  local chosen = false

  local function lbl(text, yPos, size, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.8, 0, 0, size)
    l.Position = UDim2.new(0.1, 0, 0, yPos)
    l.BackgroundTransparency = 1
    l.TextColor3 = color or AMBER
    l.Font = Enum.Font.RobotoMono
    l.TextSize = size > 40 and 28 or 14
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.TextWrapped = true
    l.ZIndex = 30
    l.Text = text
    l.Parent = frame
    return l
  end

  local function makeBtn(label, desc, yPos, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.8, 0, 0, 70)
    btn.Position = UDim2.new(0.1, 0, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    btn.BorderColor3 = AMBER
    btn.BorderSizePixel = 1
    btn.TextColor3 = GREEN
    btn.Font = Enum.Font.RobotoMono
    btn.TextSize = 13
    btn.TextWrapped = true
    btn.ZIndex = 30
    btn.Text = label .. "\n" .. desc
    btn.Parent = frame
    btn.Activated:Connect(onClick)
    return btn
  end

  local function pick(mode)
    if chosen then return end
    chosen = true
    if conn then conn:Disconnect(); conn = nil end
    onPicked(mode)
  end

  lbl("TAIPAN!", 40, 60)
  lbl("Choose your interface style:", 120, 28)

  makeBtn("[M] Modern",   "touch-friendly panels",             190, function() pick("modern") end)
  makeBtn("[A] Apple II", "keyboard terminal, authentic style", 270, function() pick("apple2") end)

  lbl("(You can change this later from Settings at any port)", 355, 24, DIM)

  conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.M then pick("modern")
    elseif input.KeyCode == Enum.KeyCode.A then pick("apple2")
    end
  end)

  local adapter = {}
  function adapter.update(_state)  end   -- no-op: bootstrapper drives everything
  function adapter.notify(_msg)    end
  function adapter.destroy()
    if conn then conn:Disconnect() end
    frame:Destroy()
  end

  return adapter
end

return InterfacePicker
```

- [ ] **Step 2: Inject into Studio via MCP**

Use `mcp__Roblox_Studio__script_read` on `StarterGui.TaipanGui.InterfacePicker` to get the current Studio script, then `mcp__Roblox_Studio__multi_edit` (or `execute_luau` to fully replace the script source).

- [ ] **Step 3: Commit**

```bash
git add src/StarterGui/TaipanGui/InterfacePicker.lua
git commit -m "feat: InterfacePicker Phase 1 only with onPicked callback"
```

---

## Task 7: Update `init.client.lua` — wire `onPicked`, immediate adapter creation

**Files:**
- Modify: `src/StarterGui/TaipanGui/init.client.lua`

### Context

Current `init.client.lua`:
- Creates `InterfacePicker.new(screenGui, GameActions)` (no callback)
- `makeAdapter(mode)` helper creates the right adapter
- `StateUpdate` handler switches adapters reactively

New behaviour:
- Pass `onPicked` callback as third arg to InterfacePicker
- In callback: destroy picker, fire `SetUIMode`, create correct adapter
  - Apple II: also call `adapter.update({})` to show `sceneStartChoice`
  - Modern: no `update()` needed (StartPanel visible from constructor)
- Remove `makeAdapter` helper (no longer needed — adapter creation is now inline in callback and StateUpdate)
- `StateUpdate` handler: when `currentMode == "picker"` and `targetMode ~= nil`, this is a returning player — destroy picker, create adapter, update. This path already exists in the current handler and works unchanged.

- [ ] **Step 1: Edit `init.client.lua` on disk**

Replace the entire file:
```lua
-- init.client.lua  (LocalScript inside TaipanGui ScreenGui)
-- Bootstrapper: shows InterfacePicker immediately, then delegates to the right adapter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- Taipan is pure 2D: hide the 3D world behind a full-screen black backdrop.
-- CharacterAutoLoads=false (set server-side) means no avatar spawns,
-- so key presses are never consumed by character movement scripts.
do
  local backdrop = Instance.new("ScreenGui")
  backdrop.Name            = "Backdrop"
  backdrop.DisplayOrder    = -10
  backdrop.ResetOnSpawn    = false
  backdrop.IgnoreGuiInset  = true
  backdrop.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
  backdrop.Parent          = Players.LocalPlayer.PlayerGui

  local fill = Instance.new("Frame")
  fill.Size                  = UDim2.fromScale(1, 1)
  fill.BackgroundColor3      = Color3.new(0, 0, 0)
  fill.BackgroundTransparency = 0
  fill.BorderSizePixel       = 0
  fill.Parent                = backdrop
end

-- Point camera away from the world so nothing leaks through transparent areas.
local camera = workspace.CurrentCamera
camera.CameraType = Enum.CameraType.Scriptable
camera.CFrame     = CFrame.new(0, 1e6, 0)

local Remotes           = require(ReplicatedStorage.Remotes)
local GameActions       = require(script.GameActions)
local ModernInterface   = require(script.ModernInterface)
local InterfacePicker   = require(script.InterfacePicker)
local Apple2Interface   = require(script.Apple2Interface)

local screenGui = script.Parent   -- TaipanGui ScreenGui
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Show picker immediately — no wait for StateUpdate.
-- onPicked fires when the player selects an interface style.
local currentMode    = "picker"
local currentAdapter = InterfacePicker.new(screenGui, GameActions, function(mode)
  currentAdapter.destroy()
  GameActions.setUIMode(mode)   -- server stores pendingMode (no state yet)

  if mode == "apple2" then
    currentAdapter = Apple2Interface.new(screenGui, GameActions)
    currentMode    = "apple2"
    currentAdapter.update({})   -- empty state → sceneStartChoice renders
  else  -- "modern"
    currentAdapter = ModernInterface.new(screenGui, GameActions)
    currentMode    = "modern"
    -- no update() needed — StartPanel is visible from constructor
  end
end)

Remotes.StateUpdate.OnClientEvent:Connect(function(state)
  if type(state) ~= "table" then return end   -- sentinel guard (boolean during DataStore load)

  local targetMode = state.uiMode  -- nil | "modern" | "apple2"

  if currentMode == "picker" then
    if targetMode ~= nil then
      -- Returning player: StateUpdate arrived before picker was interacted with.
      -- Destroy picker and show the saved game using the stored interface.
      currentAdapter.destroy()
      if targetMode == "apple2" then
        currentAdapter = Apple2Interface.new(screenGui, GameActions)
      else
        currentAdapter = ModernInterface.new(screenGui, GameActions)
      end
      currentMode = targetMode
    else
      -- StateUpdate arrived but no interface chosen yet (shouldn't happen in normal flow).
      return
    end

  elseif (currentMode == "modern" or currentMode == "apple2")
      and targetMode ~= nil
      and targetMode ~= currentMode then
    -- Live interface switch from Settings
    currentAdapter.destroy()
    if targetMode == "apple2" then
      currentAdapter = Apple2Interface.new(screenGui, GameActions)
    else
      currentAdapter = ModernInterface.new(screenGui, GameActions)
    end
    currentMode = targetMode
  end

  currentAdapter.update(state)
end)

Remotes.Notify.OnClientEvent:Connect(function(message)
  if currentAdapter then currentAdapter.notify(message) end
end)
```

- [ ] **Step 2: Inject into Studio via MCP**

- [ ] **Step 3: Verify in Studio — new player Apple II path**

Start Play. InterfacePicker appears. Press A (Apple II). Terminal should render "Do you have a firm, or a ship?" immediately. Press F. Port scene should appear. ✓

- [ ] **Step 4: Verify in Studio — new player Modern path**

Start Play. Press M (Modern). StartPanel should appear. Click Firm. Port panels should appear. ✓

- [ ] **Step 5: Commit**

```bash
git add src/StarterGui/TaipanGui/init.client.lua
git commit -m "feat: wire onPicked callback; immediate adapter creation on interface pick"
```

---

## Task 8: End-to-end verification

### New player flows (Studio)

- [ ] **Apple II**: Start Play → press A → terminal shows "Do you have a firm, or a ship?" → press F → port scene in terminal ✓
- [ ] **Apple II guns start**: Start Play → press A → press S → port scene in terminal ✓
- [ ] **Modern**: Start Play → press M → StartPanel shows → click Firm → port panels ✓
- [ ] **Key shortcuts in picker**: press M and A keys work; buttons work

### Returning player flow (production only — DataStore bypassed in Studio)

- [ ] In a live Roblox game (or Studio with DataStore enabled via a test key): connect with an existing save → picker appears briefly → StateUpdate arrives → correct adapter loaded with saved state, no start choice screen shown ✓

### Edge cases

- [ ] Pressing A rapidly twice in the picker → only one onPicked fires (`chosen` guard)
- [ ] Switching interface from Settings mid-game → correct adapter shown

---

## Task 9: Final commit

- [ ] **Confirm all files committed**

```bash
git log --oneline -8
git status
```

Expected: clean working tree, all 5 files in recent commits.
