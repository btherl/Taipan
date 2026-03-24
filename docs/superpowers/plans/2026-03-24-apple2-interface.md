# Apple II Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Apple II–style full-screen keyboard terminal as a selectable alternative to the existing touch panel UI, with live switching and persistent preference.

**Architecture:** A thin bootstrapper (`init.client.lua`) reads `state.uiMode` from each StateUpdate and delegates to one of three adapters — `InterfacePicker`, `ModernInterface`, or `Apple2Interface` — all sharing the same three-method contract (`update/notify/destroy`). The existing 13 panel files are untouched; `ModernInterface` wraps them. The Apple II interface uses the existing `Text` bitmap font library with `TaipanStandardFont` to render a 40-column terminal.

**Tech Stack:** Luau (Roblox), Rojo (file sync), MCP Studio tools (script patching), existing `ReplicatedStorage.Text` bitmap font library, `UserInputService` for keyboard/touch input.

---

## Critical Workflow Note (Roblox)

Rojo does **not** auto-sync. For every file you create or edit:
1. Write the `.lua` file on disk (for git)
2. Use `mcp__Roblox_Studio__script_write` to push the same content into the running Studio session
3. Verify in Studio Play or Run mode

Studio path conventions:
- `src/StarterGui/TaipanGui/Foo.lua` → Studio path `StarterGui.TaipanGui.Foo`
- `src/StarterGui/TaipanGui/Apple2/Bar.lua` → Studio path `StarterGui.TaipanGui.Apple2.Bar`
- `src/ReplicatedStorage/Remotes.lua` → Studio path `ReplicatedStorage.Remotes`
- `src/ServerScriptService/GameService.server.lua` → Studio path `ServerScriptService.GameService`

## How to Test (Roblox-Specific)

Unit tests (TestEZ) run only in Studio **Run** mode and cover server-side engine modules in `tests/`. Client-side UI modules have no TestEZ coverage — verify them by playing in Studio **Play** mode and checking the Output panel for errors.

To simulate a new player (no save), test the `SetUIMode` handler by calling it from the Studio Command Bar or temporarily adding a print to `GameService`.

---

## File Map

**Create (new):**
- `src/StarterGui/TaipanGui/GameActions.lua`
- `src/StarterGui/TaipanGui/InterfacePicker.lua`
- `src/StarterGui/TaipanGui/ModernInterface.lua`
- `src/StarterGui/TaipanGui/Apple2Interface.lua`
- `src/StarterGui/TaipanGui/Apple2/Terminal.lua`
- `src/StarterGui/TaipanGui/Apple2/GlitchLayer.lua`
- `src/StarterGui/TaipanGui/Apple2/KeyInput.lua`
- `src/StarterGui/TaipanGui/Apple2/PromptEngine.lua`

**Modify (surgical edits):**
- `src/ReplicatedStorage/Remotes.lua` — add `SetUIMode` RemoteEvent
- `src/ReplicatedStorage/shared/GameState.lua` — add `uiMode = nil` field
- `src/ServerScriptService/GameService.server.lua` — add `SetUIMode` handler
- `src/StarterGui/TaipanGui/init.client.lua` — replace with bootstrapper

**Untouched:** All 13 panel files, all engine modules, all test specs, `Text/` library.

---

## Task 1: Add `SetUIMode` to Remotes, GameState, and GameService

**Files:**
- Modify: `src/ReplicatedStorage/Remotes.lua`
- Modify: `src/ReplicatedStorage/shared/GameState.lua`
- Modify: `src/ServerScriptService/GameService.server.lua`

- [ ] **Step 1: Add `SetUIMode` to Remotes.lua**

In `src/ReplicatedStorage/Remotes.lua`, add one line after the `QuitGame` line (around line 53):

```lua
Remotes.SetUIMode      = getOrCreate("RemoteEvent", "SetUIMode")      -- client->server: "modern" or "apple2"
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `ReplicatedStorage.Remotes`.

- [ ] **Step 2: Add `uiMode` field to GameState.lua**

In `src/ReplicatedStorage/shared/GameState.lua`, add one line inside the `state = { ... }` table, after `seenTutorial = false`:

```lua
    uiMode = nil,   -- nil = not yet chosen; "modern" or "apple2" once set
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `ReplicatedStorage.shared.GameState`.

- [ ] **Step 3: Add `SetUIMode` handler to GameService.server.lua**

In `src/ServerScriptService/GameService.server.lua`, add this block immediately before the `game:BindToClose` line (around line 646):

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

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `ServerScriptService.GameService`.

- [ ] **Step 4: Verify in Studio Run mode**

Click **Run** in Studio (not Play). Open the Output panel. No errors should appear. If there are Remotes-related errors, check that `SetUIMode` was added to the `Remotes` table correctly.

- [ ] **Step 5: Commit**

```bash
git add src/ReplicatedStorage/Remotes.lua \
        src/ReplicatedStorage/shared/GameState.lua \
        src/ServerScriptService/GameService.server.lua
git commit -m "feat: add SetUIMode remote, uiMode state field, and server handler"
```

---

## Task 2: Create `GameActions.lua`

**Files:**
- Create: `src/StarterGui/TaipanGui/GameActions.lua`

- [ ] **Step 1: Write `GameActions.lua`**

```lua
-- GameActions.lua
-- Shared Remote wrappers. Both interfaces import this; neither calls Remotes directly.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui.GameActions` (create as ModuleScript).

- [ ] **Step 2: Commit**

```bash
git add src/StarterGui/TaipanGui/GameActions.lua
git commit -m "feat: add GameActions shared Remote wrapper module"
```

---

## Task 3: Create `ModernInterface.lua`

This extracts the panel-wiring code currently in `init.client.lua` into the adapter contract. The existing 13 panel files are **not changed**.

**Files:**
- Create: `src/StarterGui/TaipanGui/ModernInterface.lua`

- [ ] **Step 1: Write `ModernInterface.lua`**

```lua
-- ModernInterface.lua
-- Adapter wrapping all 13 existing panels. Implements { update, notify, destroy }.
-- Existing panel files are untouched.

local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Panels         = script.Parent.Panels
local StatusStrip    = require(Panels.StatusStrip)
local InventoryPanel = require(Panels.InventoryPanel)
local PricesPanel    = require(Panels.PricesPanel)
local BuySellPanel   = require(Panels.BuySellPanel)
local PortPanel      = require(Panels.PortPanel)
local WarehousePanel = require(Panels.WarehousePanel)
local WuPanel        = require(Panels.WuPanel)
local BankPanel      = require(Panels.BankPanel)
local MessagePanel   = require(Panels.MessagePanel)
local GameOverPanel  = require(Panels.GameOverPanel)
local CombatPanel    = require(Panels.CombatPanel)
local ShipPanel      = require(Panels.ShipPanel)
local StartPanel     = require(Panels.StartPanel)

local AMBER = Color3.fromRGB(200, 180, 80)
local GREEN = Color3.fromRGB(140, 200, 80)
local DIM   = Color3.fromRGB(80, 80, 80)

local ModernInterface = {}

function ModernInterface.new(screenGui, actions)
  -- Root frame: 480px wide column
  local root = Instance.new("Frame")
  root.Name = "Root"
  root.Size = UDim2.new(0, 480, 1, 0)
  root.Position = UDim2.new(0, 0, 0, 0)
  root.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  root.BorderSizePixel = 0
  root.Parent = screenGui

  -- Instantiate all panels (same wiring as original init.client.lua)
  local portPanel = PortPanel.new(root,
    function(dest) actions.travelTo(dest) end,
    function() actions.retire() end,
    function() actions.quitGame() end
  )
  local statusStrip    = StatusStrip.new(root)
  local inventoryPanel = InventoryPanel.new(root)
  local pricesPanel    = PricesPanel.new(root)
  local buySellPanel   = BuySellPanel.new(root,
    function(g, q) actions.buyGoods(g, q) end,
    function(g, q) actions.sellGoods(g, q) end,
    function() actions.endTurn() end
  )
  local warehousePanel = WarehousePanel.new(root,
    function(g, q) actions.transferTo(g, q) end,
    function(g, q) actions.transferFrom(g, q) end
  )
  local messagePanel = MessagePanel.new(root)
  local wuPanel = WuPanel.new(root,
    function(amt) actions.wuRepay(amt) end,
    function(amt) actions.wuBorrow(amt) end,
    function() actions.leaveWu() end,
    function() actions.buyLiYuen() end
  )
  local bankPanel = BankPanel.new(root,
    function(amt) actions.bankDeposit(amt) end,
    function(amt) actions.bankWithdraw(amt) end
  )
  local gameOverPanel = GameOverPanel.new(root, function() actions.restartGame() end)
  local combatPanel   = CombatPanel.new(root,
    function() actions.combatFight() end,
    function() actions.combatRun() end,
    function(g, q) actions.combatThrow(g, q) end
  )
  local shipPanel = ShipPanel.new(root,
    function(amt) actions.shipRepair(amt) end,
    function() actions.acceptUpgrade() end,
    function() actions.declineUpgrade() end,
    function() actions.acceptGun() end,
    function() actions.declineGun() end,
    function() actions.shipPanelDone() end
  )
  local startPanel = StartPanel.new(root, function(choice)
    actions.chooseStart(choice)
    actions.requestState()
  end)

  -- Standalone settings button (not inside any panel)
  -- Positioned at top-right of the PortPanel region
  local settingsOverlay = nil  -- created on demand

  local function showSettingsOverlay(currentMode)
    if settingsOverlay then return end
    settingsOverlay = Instance.new("Frame")
    settingsOverlay.Name = "SettingsOverlay"
    settingsOverlay.Size = UDim2.new(1, 0, 0, 80)
    settingsOverlay.Position = UDim2.new(0, 0, 0, 30)
    settingsOverlay.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    settingsOverlay.BorderColor3 = AMBER
    settingsOverlay.BorderSizePixel = 1
    settingsOverlay.ZIndex = 25
    settingsOverlay.Parent = root

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 24)
    lbl.Position = UDim2.new(0, 5, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = AMBER
    lbl.Font = Enum.Font.RobotoMono
    lbl.TextSize = 12
    lbl.Text = "Switch interface?"
    lbl.ZIndex = 25
    lbl.Parent = settingsOverlay

    local function makeBtn(label, posX, mode)
      local btn = Instance.new("TextButton")
      btn.Size = UDim2.new(0.3, -4, 0, 36)
      btn.Position = UDim2.new(posX, 2, 0, 36)
      btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
      btn.BorderColor3 = AMBER
      btn.TextColor3 = (mode == currentMode) and DIM or GREEN
      btn.Font = Enum.Font.RobotoMono
      btn.TextSize = 11
      btn.Text = label
      btn.ZIndex = 25
      btn.Parent = settingsOverlay
      btn.Activated:Connect(function()
        settingsOverlay:Destroy()
        settingsOverlay = nil
        if mode and mode ~= currentMode then
          actions.setUIMode(mode)
        end
      end)
    end

    makeBtn("Modern",   0,    "modern")
    makeBtn("Apple II", 0.33, "apple2")
    makeBtn("Cancel",   0.67, nil)
  end

  local settingsBtn = Instance.new("TextButton")
  settingsBtn.Name = "SettingsBtn"
  settingsBtn.Size = UDim2.new(0, 60, 0, 22)
  settingsBtn.Position = UDim2.new(1, -62, 0, 4)
  settingsBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
  settingsBtn.BorderColor3 = Color3.fromRGB(80, 80, 80)
  settingsBtn.TextColor3 = Color3.fromRGB(120, 120, 120)
  settingsBtn.Font = Enum.Font.RobotoMono
  settingsBtn.TextSize = 10
  settingsBtn.Text = "⚙ UI"
  settingsBtn.ZIndex = 5
  settingsBtn.Visible = false
  settingsBtn.Parent = root

  local latestUIMode = "modern"
  settingsBtn.Activated:Connect(function()
    if settingsOverlay then
      settingsOverlay:Destroy(); settingsOverlay = nil
    else
      showSettingsOverlay(latestUIMode)
    end
  end)

  local adapter = {}

  function adapter.update(state)
    startPanel.hide()  -- idempotent: destroys frame on first call, no-op thereafter
    portPanel.update(state)
    statusStrip.update(state)
    inventoryPanel.update(state)
    pricesPanel.update(state)
    buySellPanel.update(state)
    warehousePanel.update(state)
    wuPanel.update(state)
    bankPanel.update(state)
    gameOverPanel.update(state)
    combatPanel.update(state)
    shipPanel.update(state)

    latestUIMode = state.uiMode or "modern"
    local canSettings = not state.gameOver
      and state.combat == nil
      and state.shipOffer == nil
    settingsBtn.Visible = canSettings
    if not canSettings and settingsOverlay then
      settingsOverlay:Destroy(); settingsOverlay = nil
    end
  end

  function adapter.notify(message)
    messagePanel.show(message)
  end

  function adapter.destroy()
    root:Destroy()
  end

  return adapter
end

return ModernInterface
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui.ModernInterface` (ModuleScript).

- [ ] **Step 2: Commit**

```bash
git add src/StarterGui/TaipanGui/ModernInterface.lua
git commit -m "feat: add ModernInterface adapter wrapping all 13 existing panels"
```

---

## Task 4: Create `InterfacePicker.lua`

**Files:**
- Create: `src/StarterGui/TaipanGui/InterfacePicker.lua`

- [ ] **Step 1: Write `InterfacePicker.lua`**

```lua
-- InterfacePicker.lua
-- Shown when state.uiMode == nil (new player, no preference saved).
-- Implements the adapter contract: update() and notify() are no-ops.
local UserInputService = game:GetService("UserInputService")

local AMBER = Color3.fromRGB(200, 180, 80)
local GREEN = Color3.fromRGB(140, 200, 80)

local InterfacePicker = {}

function InterfacePicker.new(screenGui, actions)
  local frame = Instance.new("Frame")
  frame.Name = "InterfacePicker"
  frame.Size = UDim2.new(1, 0, 1, 0)
  frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
  frame.BorderSizePixel = 0
  frame.ZIndex = 30
  frame.Parent = screenGui

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

  lbl("TAIPAN!", 40, 60)
  lbl("Choose your interface:", 120, 28)

  local chosen = false
  local conn   -- keyboard connection

  local function pick(mode)
    if chosen then return end
    chosen = true
    if conn then conn:Disconnect() end
    actions.setUIMode(mode)
    -- Bootstrapper will detect state.uiMode change and call destroy() + instantiate real adapter
  end

  local function makeBtn(label, desc, yPos, mode)
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
    btn.Activated:Connect(function() pick(mode) end)
  end

  makeBtn("[M] Modern",   "touch-friendly panels",           170, "modern")
  makeBtn("[A] Apple II", "keyboard terminal, authentic style", 260, "apple2")

  lbl("(You can change this later from the Settings option at port)", 350, 28, Color3.fromRGB(120, 120, 120))

  -- Keyboard shortcut: M or A
  conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.M then pick("modern")
    elseif input.KeyCode == Enum.KeyCode.A then pick("apple2")
    end
  end)

  local adapter = {}
  function adapter.update(_state)  end   -- no-op
  function adapter.notify(_msg)    end   -- no-op
  function adapter.destroy()
    if conn then conn:Disconnect() end
    frame:Destroy()
  end
  return adapter
end

return InterfacePicker
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui.InterfacePicker` (ModuleScript).

- [ ] **Step 2: Commit**

```bash
git add src/StarterGui/TaipanGui/InterfacePicker.lua
git commit -m "feat: add InterfacePicker overlay for first-time interface selection"
```

---

## Task 5: Replace `init.client.lua` with Bootstrapper

**Files:**
- Modify: `src/StarterGui/TaipanGui/init.client.lua`

- [ ] **Step 1: Replace `init.client.lua`**

The entire file is replaced. The current content wires all 13 panels directly — that logic now lives in `ModernInterface.lua`.

```lua
-- init.client.lua  (LocalScript inside TaipanGui ScreenGui)
-- Bootstrapper: reads state.uiMode, delegates to the right adapter.
-- Does not know about any specific panel or interface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes           = require(ReplicatedStorage.Remotes)
local GameActions       = require(script.GameActions)
local ModernInterface   = require(script.ModernInterface)
local InterfacePicker   = require(script.InterfacePicker)
local Apple2Interface   = require(script.Apple2Interface)

local screenGui = script.Parent   -- TaipanGui ScreenGui
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local currentMode    = nil   -- nil | "picker" | "modern" | "apple2"
local currentAdapter = nil

local function makeAdapter(mode)
  if mode == "modern"  then return ModernInterface.new(screenGui, GameActions) end
  if mode == "apple2"  then return Apple2Interface.new(screenGui, GameActions) end
  return InterfacePicker.new(screenGui, GameActions)   -- nil → picker
end

Remotes.StateUpdate.OnClientEvent:Connect(function(state)
  if type(state) ~= "table" then return end   -- sentinel guard (boolean during DataStore load)

  local targetMode = state.uiMode  -- nil | "modern" | "apple2"

  if currentMode == nil then
    -- First real state: instantiate the appropriate adapter
    local label = targetMode or "picker"
    currentAdapter = makeAdapter(targetMode)
    currentMode    = label

  elseif currentMode == "picker" and targetMode ~= nil then
    -- Player just picked an interface
    currentAdapter.destroy()
    currentAdapter = makeAdapter(targetMode)
    currentMode    = targetMode

  elseif (currentMode == "modern" or currentMode == "apple2")
      and targetMode ~= nil
      and targetMode ~= currentMode then
    -- Live interface switch
    currentAdapter.destroy()
    currentAdapter = makeAdapter(targetMode)
    currentMode    = targetMode
  end

  currentAdapter.update(state)
end)

Remotes.Notify.OnClientEvent:Connect(function(message)
  if currentAdapter then currentAdapter.notify(message) end
end)
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui` (the LocalScript itself — the init script of TaipanGui).

- [ ] **Step 2: Verify Modern UI still works end-to-end**

In Studio, click **Play**. Expected:
- InterfacePicker appears (new player: no `uiMode` saved)
- Press M → picker disappears, modern UI appears (480px column, all panels visible)
- Start as "Firm", trade goods, travel to a port — all existing functionality works
- Settings button (⚙ UI) is visible at port; clicking shows the switch overlay
- Output panel: no errors

If you have an existing save with no `uiMode`, the picker appears once. After picking, `uiMode` is saved; subsequent joins skip the picker.

To test with a saved `uiMode = "modern"`: after picking once, stop and restart Play — modern UI should appear immediately without the picker.

- [ ] **Step 3: Commit**

```bash
git add src/StarterGui/TaipanGui/init.client.lua
git commit -m "refactor: replace init.client.lua with adapter bootstrapper"
```

---

## Task 6: Create `GlitchLayer.lua` (Stub)

**Files:**
- Create: `src/StarterGui/TaipanGui/Apple2/GlitchLayer.lua`

- [ ] **Step 1: Write `GlitchLayer.lua`**

```lua
-- GlitchLayer.lua
-- Stub overlay for future CRT glitch effects (scan lines, phosphor bloom, etc.).
-- The frame exists so Apple2Interface can hand it to a future implementation
-- without structural changes.

local GlitchLayer = {}

function GlitchLayer.new(terminalGui)
  -- terminalGui is the ScreenGui returned by Text.GetTextGUI()
  local frame = Instance.new("Frame")
  frame.Name = "GlitchLayer"
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

return GlitchLayer
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui.Apple2.GlitchLayer` (ModuleScript inside an `Apple2` Folder inside `TaipanGui`). Create the `Apple2` Folder in Studio first if it doesn't exist.

- [ ] **Step 2: Commit**

```bash
git add src/StarterGui/TaipanGui/Apple2/GlitchLayer.lua
git commit -m "feat: add GlitchLayer stub for future CRT effects"
```

---

## Task 7: Create `Terminal.lua`

Manages the full-screen bitmap font display using the existing `Text` library.

**Font layout reference:**
- Font: `TaipanStandardFont` (exists at `ReplicatedStorage.Text.Fonts.TaipanStandardFont`)
- Glyph size: `xadvance = 16`, `height = 16` virtual pixels
- `TextSize = 3` → each char = 48×48 virtual pixels
- 40 cols × 48 = 1920 vp (exactly fills virtual width)
- Rows 1–22 fit within 1080 vp height; rows 23–24 may be partially clipped (acceptable)
- Row `n` positioned at `Y = (n-1) * 48` virtual pixels

**Files:**
- Create: `src/StarterGui/TaipanGui/Apple2/Terminal.lua`

- [ ] **Step 1: Write `Terminal.lua`**

```lua
-- Terminal.lua
-- 24-row bitmap font display using the ReplicatedStorage.Text library.
-- Uses TaipanStandardFont at TextSize=3: 40 cols × ~22 fully-visible rows.
-- Rows 23–24 may be partially clipped (CRT overscan authenticity).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Text              = require(ReplicatedStorage.Text)

local ROWS       = 24
local TEXT_SIZE  = 3
local ROW_HEIGHT = 48   -- 16 virtual px * TextSize 3
local GREEN      = Color3.fromRGB(140, 200, 80)

local Terminal = {}

function Terminal.new(displayOrder)
  -- GetTextGUI returns a ScreenGui with TextParent frame (16:9 AspectRatioConstraint, 1920×1080 virtual)
  local gui = Text.GetTextGUI(displayOrder or 5)
  gui.Name   = "TaipanTerminal"
  gui.Parent = Players.LocalPlayer.PlayerGui

  -- Black background frame behind all text
  local bg = Instance.new("Frame")
  bg.Name               = "Background"
  bg.Size               = UDim2.fromScale(1, 1)
  bg.BackgroundColor3   = Color3.new(0, 0, 0)
  bg.BackgroundTransparency = 0
  bg.ZIndex             = 0
  bg.BorderSizePixel    = 0
  bg.Parent             = gui.TextParent

  -- Fixed pool of ROWS Text objects (one per row)
  local rows = {}
  for i = 1, ROWS do
    local t = Text.new("TaipanStandardFont", true)  -- automatic_update = true
    t.Parent    = gui.TextParent
    t.Position  = Vector2.new(0, (i - 1) * ROW_HEIGHT)
    t.TextSize  = TEXT_SIZE
    t.TextColor3 = GREEN
    t.ZIndex    = 1
    rows[i] = t
  end

  -- Buffer: which logical line is in which row slot
  -- buffer[row] = { text = string, color = Color3 }
  local buffer = {}
  for i = 1, ROWS do buffer[i] = { text = "", color = GREEN } end

  local function redrawAll()
    for i = 1, ROWS do
      rows[i].Text       = buffer[i].text
      rows[i].TextColor3 = buffer[i].color
    end
  end

  local term = {}

  function term.clear()
    for i = 1, ROWS do buffer[i] = { text = "", color = GREEN } end
    redrawAll()
  end

  -- Splits on \n and appends each segment; scrolls when full
  function term.print(text, color)
    color = color or GREEN
    -- Handle multi-line strings
    local segments = text:split("\n")
    for _, seg in ipairs(segments) do
      -- Scroll: shift buffer up, place new line at bottom (row ROWS-1, leaving row ROWS for input)
      for i = 1, ROWS - 2 do
        buffer[i] = buffer[i + 1]
      end
      buffer[ROWS - 1] = { text = seg, color = color }
      -- Row ROWS is the input line — preserve it (showInputLine manages it)
    end
    redrawAll()
  end

  -- Writes text to the dedicated input row (row ROWS) without scrolling
  function term.showInputLine(text)
    buffer[ROWS] = { text = text or "", color = GREEN }
    rows[ROWS].Text = buffer[ROWS].text
    rows[ROWS].TextColor3 = GREEN
  end

  function term.setRowColor(row, color)
    if row < 1 or row > ROWS then return end
    buffer[row].color = color
    rows[row].TextColor3 = color
  end

  function term.destroy()
    for i = 1, ROWS do
      rows[i]:Destroy()
    end
    gui:Destroy()
  end

  -- Expose the gui so GlitchLayer and Apple2Interface can reference it
  term._gui = gui

  return term
end

return Terminal
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui.Apple2.Terminal` (ModuleScript).

- [ ] **Step 2: Smoke-test Terminal in isolation**

In the Studio Command Bar (client-side), run:
```lua
local RS = game:GetService("ReplicatedStorage")
local Terminal = require(game.StarterGui.TaipanGui.Apple2.Terminal)
local t = Terminal.new(5)
t.print("TAIPAN!", Color3.fromRGB(140,200,80))
t.print("Cash: $400  Debt: $5000", Color3.fromRGB(200,180,80))
t.showInputLine("> ")
```

Expected: full-screen black background with green text visible. If you see errors about the font name, verify `TaipanStandardFont` exists under `ReplicatedStorage.Text.Fonts` in the Explorer panel.

- [ ] **Step 3: Commit**

```bash
git add src/StarterGui/TaipanGui/Apple2/Terminal.lua
git commit -m "feat: add Terminal bitmap font screen manager"
```

---

## Task 8: Create `KeyInput.lua`

**Files:**
- Create: `src/StarterGui/TaipanGui/Apple2/KeyInput.lua`

- [ ] **Step 1: Write `KeyInput.lua`**

```lua
-- KeyInput.lua
-- Handles keyboard (desktop) and virtual buttons (mobile/touch) input.
-- Calls back into Apple2Interface via promptDef callbacks.

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")

local isMobile = UserInputService.TouchEnabled

local KeyInput = {}

function KeyInput.new(screenGui)
  local connections    = {}   -- active input connections
  local mobileButtons  = {}   -- active mobile TextButton instances
  local mobileFrame    = nil  -- container for mobile buttons
  local localSceneCb   = nil  -- callback for scene-changing keys
  local typeBuf        = ""
  local typeUpdateConn = nil  -- RenderStepped for mobile TextBox mirror
  local hiddenBox      = nil  -- hidden TextBox for mobile keyboard

  -- Clean up all active listeners and mobile UI
  local function cleanup()
    for _, c in ipairs(connections) do c:Disconnect() end
    connections = {}
    if mobileFrame then mobileFrame:Destroy(); mobileFrame = nil end
    mobileButtons = {}
    if typeUpdateConn then typeUpdateConn:Disconnect(); typeUpdateConn = nil end
    if hiddenBox then hiddenBox:Destroy(); hiddenBox = nil end
    typeBuf = ""
  end

  -- Build mobile virtual key buttons for "key" mode
  local function buildMobileButtons(keys, onPress)
    mobileFrame = Instance.new("Frame")
    mobileFrame.Name = "MobileKeyRow"
    mobileFrame.Size = UDim2.new(1, 0, 0, 60)
    mobileFrame.Position = UDim2.new(0, 0, 1, -60)
    mobileFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    mobileFrame.BorderSizePixel = 0
    mobileFrame.ZIndex = 50
    mobileFrame.Parent = screenGui

    local count = #keys
    for i, key in ipairs(keys) do
      local btn = Instance.new("TextButton")
      btn.Size = UDim2.new(1 / count, -4, 1, -8)
      btn.Position = UDim2.new((i - 1) / count, 2, 0, 4)
      btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
      btn.BorderColor3 = Color3.fromRGB(100, 100, 40)
      btn.TextColor3 = Color3.fromRGB(200, 180, 80)
      btn.Font = Enum.Font.RobotoMono
      btn.TextSize = 18
      btn.ZIndex = 50
      btn.Text = key
      btn.Parent = mobileFrame
      btn.Activated:Connect(function() onPress(key) end)
      table.insert(mobileButtons, btn)
    end
  end

  local ki = {}

  -- Called by Apple2Interface to register callback for local-scene key presses
  function ki.setLocalSceneCallback(cb)
    localSceneCb = cb
  end

  -- Called by Apple2Interface whenever the active promptDef changes
  function ki.setPrompt(promptDef, state, actions)
    cleanup()
    if not promptDef then return end

    if promptDef.type == "key" then
      -- Build a set of valid keys (uppercase) for fast lookup
      local validKeys = {}
      for _, k in ipairs(promptDef.keys) do
        validKeys[k:upper()] = true
      end

      local function onPress(key)
        key = key:upper()
        if validKeys[key] then
          promptDef.onKey(key, state, actions)
        end
      end

      if isMobile then
        buildMobileButtons(promptDef.keys, onPress)
      else
        table.insert(connections,
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            local name = input.KeyCode.Name  -- e.g. "F", "R", "T", "Exclamation"
            -- Map common keys to their character
            local char = name
            if #name == 1 then char = name:upper()
            elseif name == "Exclamation" then char = "!"
            elseif name == "Escape" then char = "C"   -- Escape acts as Cancel
            end
            onPress(char)
          end)
        )
      end

    elseif promptDef.type == "type" then
      local placeholder = promptDef.typePlaceholder or "> "

      if isMobile then
        -- Hidden TextBox triggers native on-screen keyboard
        hiddenBox = Instance.new("TextBox")
        hiddenBox.Size = UDim2.new(0, 1, 0, 1)
        hiddenBox.Position = UDim2.new(0, -10, 0, -10)
        hiddenBox.BackgroundTransparency = 1
        hiddenBox.Text = ""
        hiddenBox.Parent = screenGui
        hiddenBox:CaptureFocus()

        -- Mirror TextBox content to terminal each frame
        local terminal = promptDef._terminal  -- Apple2Interface sets this
        typeUpdateConn = RunService.RenderStepped:Connect(function()
          if terminal then terminal.showInputLine(placeholder .. hiddenBox.Text) end
        end)

        table.insert(connections,
          hiddenBox.FocusLost:Connect(function(enterPressed)
            if enterPressed then
              local submitted = hiddenBox.Text
              hiddenBox.Text = ""
              local err = promptDef.onType(submitted, state, actions)
              if err and promptDef._onError then promptDef._onError(err) end
            end
          end)
        )
      else
        -- Desktop: capture character-by-character
        local terminal = promptDef._terminal
        if terminal then terminal.showInputLine(placeholder) end

        table.insert(connections,
          UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.KeyCode == Enum.KeyCode.Return then
              local submitted = typeBuf
              typeBuf = ""
              if terminal then terminal.showInputLine(placeholder) end
              local err = promptDef.onType(submitted, state, actions)
              if err and promptDef._onError then promptDef._onError(err) end
            elseif input.KeyCode == Enum.KeyCode.Backspace then
              typeBuf = typeBuf:sub(1, -2)
              if terminal then terminal.showInputLine(placeholder .. typeBuf) end
            else
              local char = input.KeyCode.Name
              if #char == 1 then
                typeBuf = typeBuf .. char
                if terminal then terminal.showInputLine(placeholder .. typeBuf) end
              end
            end
          end)
        )
      end
    end
  end

  function ki.destroy()
    cleanup()
  end

  return ki
end

return KeyInput
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui.Apple2.KeyInput` (ModuleScript).

- [ ] **Step 2: Commit**

```bash
git add src/StarterGui/TaipanGui/Apple2/KeyInput.lua
git commit -m "feat: add KeyInput handler for keyboard and mobile virtual keys"
```

---

## Task 9: Create `PromptEngine.lua` — Port and Startup Scenes

This task covers the AtPort and StartChoice scenes. The other scenes follow in Task 10.

**Files:**
- Create: `src/StarterGui/TaipanGui/Apple2/PromptEngine.lua`

- [ ] **Step 1: Write the core `PromptEngine.lua` (AtPort + StartChoice + scaffold)**

```lua
-- PromptEngine.lua
-- Maps (state, localScene) → { lines: string[], promptDef: table }
-- Pure logic: no Roblox service calls except require.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.shared.Constants)

local HONG_KONG = Constants.HONG_KONG
local PORT_NAMES = Constants.PORT_NAMES
local MONTH_NAMES = Constants.MONTH_NAMES
local GOOD_NAMES = Constants.GOOD_NAMES

local GREEN  = Color3.fromRGB(140, 200, 80)
local AMBER  = Color3.fromRGB(200, 180, 80)
local RED    = Color3.fromRGB(220, 80, 80)
local ORANGE = Color3.fromRGB(220, 120, 60)
local DIM    = Color3.fromRGB(80, 80, 80)

local PromptEngine = {}

-- Helpers
local function pad(s, width)
  s = tostring(s)
  while #s < width do s = s .. " " end
  return s
end

local function fmt(n)
  -- Format number with commas
  local s = tostring(math.floor(n))
  local result = ""
  local count = 0
  for i = #s, 1, -1 do
    if count > 0 and count % 3 == 0 then result = "," .. result end
    result = s:sub(i, i) .. result
    count = count + 1
  end
  return "$" .. result
end

local function statusLines(state)
  local lines = {}
  local portName = PORT_NAMES[state.currentPort] or "?"
  local dateStr  = MONTH_NAMES[state.month] .. " " .. tostring(state.year)
  table.insert(lines, { text = pad(portName:upper(), 28) .. dateStr, color = AMBER })
  table.insert(lines, { text = string.format("Cash: %s  Debt: %s  Bank: %s  Guns: %d",
    fmt(state.cash), fmt(state.debt), fmt(state.bankBalance), state.guns), color = AMBER })
  local sw = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))
  table.insert(lines, { text = string.format("Hold: %d/%d  Damage: %d%%",
    state.holdSpace or 0, state.shipCapacity or 0, 100 - sw), color = AMBER })
  return lines
end

local function priceLines(state)
  local lines = {}
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "Prices:", color = AMBER })
  local prices = state.currentPrices or {0,0,0,0}
  for i = 1, 4 do
    local name = pad(GOOD_NAMES[i] .. ":", 14)
    local price = fmt(prices[i])
    table.insert(lines, { text = "  " .. name .. price, color = GREEN })
  end
  return lines
end

local function atPortMenu(state)
  -- Build the action menu based on what is available
  local isHK = (state.currentPort == HONG_KONG)
  local nw    = (state.cash or 0) + (state.bankBalance or 0) - (state.debt or 0)
  local canRetire = isHK and nw >= 1000000

  local menuParts = { "(B)uy  (S)ell  (T)ravel" }
  if isHK then
    table.insert(menuParts, "(W)arehouse  (K)Bank")
  end
  if canRetire then
    table.insert(menuParts, "(R)etire")
  end
  table.insert(menuParts, "(!)Settings  (Q)uit")

  local validKeys = {"B", "S", "T", "!", "Q"}
  if isHK then
    table.insert(validKeys, "W")
    table.insert(validKeys, "K")
  end
  if canRetire then table.insert(validKeys, "R") end

  return table.concat(menuParts, "  "), validKeys
end

-- Scene: AtPort
local function sceneAtPort(state, actions, localSceneCb)
  local lines = {}
  for _, l in ipairs(statusLines(state)) do table.insert(lines, l) end
  for _, l in ipairs(priceLines(state)) do table.insert(lines, l) end
  table.insert(lines, { text = "", color = AMBER })

  local menuStr, validKeys = atPortMenu(state)
  table.insert(lines, { text = menuStr, color = GREEN })

  local promptDef = {
    type = "key",
    keys = validKeys,
    label = menuStr,
    onKey = function(key, _state, _actions)
      if key == "B" or key == "S" then
        if localSceneCb then localSceneCb(key == "B" and "buy" or "sell") end
      elseif key == "W" then
        if localSceneCb then localSceneCb("warehouse") end
      elseif key == "K" then
        if localSceneCb then localSceneCb("bank") end
      elseif key == "T" then
        if localSceneCb then localSceneCb("travel") end
      elseif key == "R" then
        actions.retire()
      elseif key == "Q" then
        actions.quitGame()
      elseif key == "!" then
        if localSceneCb then localSceneCb("settings") end
      end
    end,
  }
  return lines, promptDef
end

-- Scene: Travel port selector
local function sceneTravel(state, actions, localSceneCb)
  local lines = {}
  for _, l in ipairs(statusLines(state)) do table.insert(lines, l) end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "Sail to which port?", color = AMBER })
  local validKeys = {"C"}
  for i = 1, 7 do
    if i ~= state.currentPort then
      table.insert(lines, { text = string.format("  [%d] %s", i, PORT_NAMES[i]), color = GREEN })
      table.insert(validKeys, tostring(i))
    end
  end
  table.insert(lines, { text = "  [C] Cancel", color = DIM })

  return lines, {
    type = "key",
    keys = validKeys,
    label = "Select port number or C to cancel",
    onKey = function(key, _state, _actions)
      if key == "C" then
        if localSceneCb then localSceneCb(nil) end
      else
        local dest = tonumber(key)
        if dest and dest >= 1 and dest <= 7 and dest ~= state.currentPort then
          actions.travelTo(dest)
          if localSceneCb then localSceneCb(nil) end
        end
      end
    end,
  }
end

-- Scene: StartChoice
local function sceneStartChoice(_state, actions, _localSceneCb)
  local lines = {
    { text = "TAIPAN!",                                          color = AMBER },
    { text = "",                                                  color = AMBER },
    { text = "Elder Brother Wu says:",                           color = AMBER },
    { text = "\"Do you have a firm, or a ship?\"",               color = AMBER },
    { text = "",                                                  color = AMBER },
    { text = "[F] FIRM — $400 cash, $5,000 debt, no guns",       color = GREEN },
    { text = "[S] SHIP — 5 guns, no cash, no debt",              color = GREEN },
  }
  return lines, {
    type = "key",
    keys = {"F", "S"},
    label = "(F)irm  (S)hip",
    onKey = function(key, _s, _a)
      if key == "F" then actions.chooseStart("cash")
      elseif key == "S" then actions.chooseStart("guns")
      end
    end,
  }
end

-- Scene: GameOver
local function sceneGameOver(state, actions, _localSceneCb)
  local reason = state.gameOverReason or "unknown"
  local lines = {
    { text = "GAME OVER", color = RED },
    { text = "",          color = AMBER },
  }
  if reason == "sunk" then
    table.insert(lines, { text = "Your ship was sunk, Taipan!", color = RED })
  elseif reason == "retired" then
    table.insert(lines, { text = "You have retired, Taipan!", color = GREEN })
    if state.finalScore then
      table.insert(lines, { text = string.format("Final score: %d (%s)",
        state.finalScore, state.finalRating or ""), color = AMBER })
    end
  elseif reason == "quit" then
    table.insert(lines, { text = "You quit, Taipan!", color = AMBER })
  end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "(R)estart", color = GREEN })

  return lines, {
    type = "key",
    keys = {"R"},
    label = "(R)estart",
    onKey = function(_key, _s, _a) actions.restartGame() end,
  }
end

-- Scene: Settings sub-prompt
local function sceneSettings(state, actions, localSceneCb)
  local currentMode = state.uiMode or "modern"
  local lines = {
    { text = "Switch interface?", color = AMBER },
    { text = "", color = AMBER },
    { text = "[M] Modern   — touch-friendly panels"  .. (currentMode == "modern"  and "  (current)" or ""), color = currentMode == "modern"  and DIM or GREEN },
    { text = "[A] Apple II — keyboard terminal"      .. (currentMode == "apple2"  and "  (current)" or ""), color = currentMode == "apple2"  and DIM or GREEN },
    { text = "[C] Cancel",                             color = AMBER },
  }
  return lines, {
    type = "key",
    keys = {"M", "A", "C"},
    label = "(M)odern  (A)pple II  (C)ancel",
    onKey = function(key, _s, _a)
      if key == "C" then
        if localSceneCb then localSceneCb(nil) end
      elseif key == "M" and currentMode ~= "modern" then
        actions.setUIMode("modern")
      elseif key == "A" and currentMode ~= "apple2" then
        actions.setUIMode("apple2")
      else
        if localSceneCb then localSceneCb(nil) end  -- already current, cancel
      end
    end,
  }
end

-- Scene: Combat
local function sceneCombat(state, actions, _localSceneCb)
  local combat = state.combat
  local total   = combat and combat.enemyTotal or 0
  local grid    = combat and combat.grid or {}
  local sw = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))

  -- Render enemy grid as ASCII: # = ship present, . = empty slot
  local gridStr = ""
  for i = 1, 10 do
    gridStr = gridStr .. (grid[i] ~= nil and "#" or ".")
  end

  local lines = {
    { text = string.format("BATTLE!!%sSW: %d%%", string.rep(" ", 22), sw),
      color = RED },
    { text = string.format("Enemy ships: %d remaining", total), color = AMBER },
    { text = "[" .. gridStr .. "]", color = GREEN },
    { text = "", color = AMBER },
    { text = "(F)ight  (R)un  (T)hrow cargo overboard", color = GREEN },
  }

  -- Include current cargo for throw context
  for i = 1, 4 do
    if (state.shipCargo[i] or 0) > 0 then
      table.insert(lines, { text = string.format("  %s: %d units", GOOD_NAMES[i], state.shipCargo[i]), color = AMBER })
    end
  end

  return lines, {
    type = "key",
    keys = {"F", "R", "T"},
    label = "(F)ight  (R)un  (T)hrow",
    onKey = function(key, _s, _a)
      if key == "F" then actions.combatFight()
      elseif key == "R" then actions.combatRun()
      elseif key == "T" then
        -- Throwing requires a follow-up: which good and how many?
        -- This is handled as a sub-prompt by the scene returning a new promptDef.
        -- For now, fire combatThrow with good 4 (General Cargo), qty 10 as default.
        -- TODO: replace with a two-step type prompt in a later iteration.
        actions.combatThrow(4, 10)
      end
    end,
  }
end

-- Scene: ShipOffers (HK only)
local function sceneShipOffers(state, actions, localSceneCb)
  local offer = state.shipOffer
  local lines = {
    { text = "[ HONG KONG — SHIP OFFERS ]", color = AMBER },
    { text = "", color = AMBER },
  }
  local keys = {"D"}  -- D = Done always available

  if offer and offer.upgradeOffer then
    table.insert(lines, { text = string.format("Upgrade ship (+50 tons) for %s", fmt(offer.upgradeOffer.cost)), color = GREEN })
    table.insert(lines, { text = "(U)pgrade  (N)o thanks", color = GREEN })
    table.insert(keys, "U")
    table.insert(keys, "N")
  end
  if offer and offer.gunOffer then
    table.insert(lines, { text = "", color = AMBER })
    table.insert(lines, { text = string.format("Buy a cannon for %s (needs 10 tons hold)", fmt(offer.gunOffer.cost)), color = GREEN })
    table.insert(lines, { text = "(G)un  (X) No cannon", color = GREEN })
    table.insert(keys, "G")
    table.insert(keys, "X")
  end
  if offer and offer.repairRate and (state.damage or 0) > 0 then
    local sw = math.max(0, 100 - math.floor((state.damage or 0) / (state.shipCapacity or 1) * 100))
    table.insert(lines, { text = "", color = AMBER })
    table.insert(lines, { text = string.format("Repair: %s/unit  SW: %d%%  Damage: %d",
      fmt(offer.repairRate), sw, math.floor(state.damage or 0)), color = AMBER })
    table.insert(lines, { text = "Enter repair amount (A=all): type number + Enter", color = GREEN })
    table.insert(keys, "R")  -- R enters repair type-mode (handled in onKey)
  end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "(D)one", color = AMBER })

  return lines, {
    type = "key",
    keys = keys,
    label = "Select option or D to finish",
    onKey = function(key, _s, _a)
      if key == "U" then actions.acceptUpgrade()
      elseif key == "N" then actions.declineUpgrade()
      elseif key == "G" then actions.acceptGun()
      elseif key == "X" then actions.declineGun()
      elseif key == "D" then actions.shipPanelDone()
      elseif key == "R" then
        -- Enter repair amount — localSceneCb switches to "repair" sub-scene
        if localSceneCb then localSceneCb("repair") end
      end
    end,
  }
end

-- Scene: WuSession (automatic on HK arrival)
local function sceneWuSession(state, actions, _localSceneCb)
  local maxRepay  = math.min(state.debt or 0, state.cash or 0)
  local maxBorrow = 2 * (state.cash or 0)
  local lines = {
    { text = "ELDER BROTHER WU",                    color = AMBER },
    { text = string.format("Debt: %s  Max repay: %s", fmt(state.debt), fmt(maxRepay)), color = AMBER },
    { text = string.format("Max borrow: %s",          fmt(maxBorrow)),                  color = AMBER },
    { text = "",                                     color = AMBER },
  }

  if state.liYuenOfferCost then
    table.insert(lines, { text = string.format("Li Yuen asks %s for protection", fmt(state.liYuenOfferCost)), color = GREEN })
    table.insert(lines, { text = "(L)i Yuen", color = GREEN })
  end

  table.insert(lines, { text = "(P)ay debt  (B)orrow  (Q)Leave Wu", color = GREEN })

  local keys = {"P", "B", "Q"}
  if state.liYuenOfferCost then table.insert(keys, "L") end

  return lines, {
    type = "key",
    keys = keys,
    label = "(P)ay  (B)orrow  (Q)Leave  (L)iYuen",
    onKey = function(key, _s, _a)
      if key == "P" then
        if _localSceneCb then _localSceneCb("wu_repay") end
      elseif key == "B" then
        if _localSceneCb then _localSceneCb("wu_borrow") end
      elseif key == "Q" then
        actions.leaveWu()
      elseif key == "L" then
        actions.buyLiYuen()
      end
    end,
  }
end

-- Sub-scenes: BuySell, Bank, Warehouse, Wu repay/borrow, Repair
local function sceneBuySell(state, actions, localSceneCb, isBuy)
  local verb = isBuy and "buy" or "sell"
  local lines = {}
  for _, l in ipairs(statusLines(state)) do table.insert(lines, l) end
  for _, l in ipairs(priceLines(state)) do table.insert(lines, l) end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = string.format("Which good to %s? (1-4) or C to cancel", verb), color = GREEN })
  for i = 1, 4 do
    local available = isBuy and (state.holdSpace or 0) or (state.shipCargo[i] or 0)
    table.insert(lines, { text = string.format("  [%d] %s (avail: %d)", i, GOOD_NAMES[i], available), color = AMBER })
  end

  return lines, {
    type = "key",
    keys = {"1","2","3","4","C"},
    label = "1-4 to select good, C to cancel",
    onKey = function(key, _s, _a)
      if key == "C" then
        if localSceneCb then localSceneCb(nil) end
      else
        local idx = tonumber(key)
        if idx and idx >= 1 and idx <= 4 then
          if localSceneCb then localSceneCb(isBuy and ("buy_good_"..idx) or ("sell_good_"..idx)) end
        end
      end
    end,
  }
end

local function sceneBuySellAmount(state, actions, localSceneCb, goodIdx, isBuy)
  local goodName  = GOOD_NAMES[goodIdx]
  local price     = (state.currentPrices or {})[goodIdx] or 0
  local maxQty    = isBuy
    and math.min(math.floor((state.cash or 0) / math.max(1, price)), state.holdSpace or 0)
    or  (state.shipCargo[goodIdx] or 0)
  local verb = isBuy and "buy" or "sell"

  local lines = {
    { text = string.format("%s %s at %s each (max %d, A=all)", verb:upper(), goodName, fmt(price), maxQty), color = AMBER },
    { text = "Amount: ", color = GREEN },
  }

  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=all): ",
    onType = function(text, _s, _a)
      local qty
      if text:upper() == "A" then qty = maxQty
      else qty = tonumber(text) end
      if not qty or qty <= 0 then return "Please enter a positive number or A for all" end
      if qty > maxQty then return string.format("You can only %s %d units", verb, maxQty) end
      if isBuy then actions.buyGoods(goodIdx, math.floor(qty))
      else           actions.sellGoods(goodIdx, math.floor(qty)) end
      if localSceneCb then localSceneCb(nil) end  -- cleared on success; StateUpdate will re-render
      return nil
    end,
  }
end

local function sceneBank(state, actions, localSceneCb)
  local lines = {
    { text = "BANK OF HONG KONG",                        color = AMBER },
    { text = string.format("Balance: %s  Cash: %s", fmt(state.bankBalance), fmt(state.cash)), color = AMBER },
    { text = "",                                          color = AMBER },
    { text = "(D)eposit  (W)ithdraw  (C)ancel",          color = GREEN },
  }
  return lines, {
    type = "key",
    keys = {"D", "W", "C"},
    label = "(D)eposit  (W)ithdraw  (C)ancel",
    onKey = function(key, _s, _a)
      if key == "D" then
        if localSceneCb then localSceneCb("bank_deposit") end
      elseif key == "W" then
        if localSceneCb then localSceneCb("bank_withdraw") end
      elseif key == "C" then
        if localSceneCb then localSceneCb(nil) end
      end
    end,
  }
end

local function sceneBankAmount(state, actions, localSceneCb, isDeposit)
  local maxAmt = isDeposit and (state.cash or 0) or (state.bankBalance or 0)
  local verb = isDeposit and "deposit" or "withdraw"
  local lines = {
    { text = string.format("%s amount (max %s, A=all):", verb:upper(), fmt(maxAmt)), color = AMBER },
    { text = "Amount: ", color = GREEN },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=all): ",
    onType = function(text, _s, _a)
      local amt
      if text:upper() == "A" then amt = maxAmt
      else amt = tonumber(text) end
      if not amt or amt <= 0 then return "Enter a positive amount or A for all" end
      if amt > maxAmt then return string.format("Max %s is %s", verb, fmt(maxAmt)) end
      if isDeposit then actions.bankDeposit(math.floor(amt))
      else              actions.bankWithdraw(math.floor(amt)) end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneWarehouse(state, actions, localSceneCb)
  local lines = {
    { text = "HONG KONG WAREHOUSE",                             color = AMBER },
    { text = string.format("Warehouse used: %d / %d",
        state.warehouseUsed or 0, Constants.WAREHOUSE_CAPACITY), color = AMBER },
    { text = "",                                                  color = AMBER },
  }
  for i = 1, 4 do
    table.insert(lines, { text = string.format("  %s — Ship: %d  Warehouse: %d",
      GOOD_NAMES[i], state.shipCargo[i] or 0, state.warehouseCargo[i] or 0), color = AMBER })
  end
  table.insert(lines, { text = "", color = AMBER })
  table.insert(lines, { text = "(T)ransfer to warehouse  (F)rom warehouse  (C)ancel", color = GREEN })

  return lines, {
    type = "key",
    keys = {"T", "F", "C"},
    label = "(T)o warehouse  (F)rom warehouse  (C)ancel",
    onKey = function(key, _s, _a)
      if key == "T" then if localSceneCb then localSceneCb("wh_to") end
      elseif key == "F" then if localSceneCb then localSceneCb("wh_from") end
      elseif key == "C" then if localSceneCb then localSceneCb(nil) end
      end
    end,
  }
end

local function sceneWarehouseGood(state, actions, localSceneCb, isToWarehouse)
  local direction = isToWarehouse and "TO warehouse" or "FROM warehouse"
  local lines = {
    { text = string.format("Transfer %s — which good?", direction), color = AMBER },
  }
  for i = 1, 4 do
    local avail = isToWarehouse and (state.shipCargo[i] or 0) or (state.warehouseCargo[i] or 0)
    table.insert(lines, { text = string.format("  [%d] %s (%d avail)", i, GOOD_NAMES[i], avail), color = AMBER })
  end
  table.insert(lines, { text = "  [C] Cancel", color = DIM })

  return lines, {
    type = "key",
    keys = {"1","2","3","4","C"},
    label = "1-4 to select, C cancel",
    onKey = function(key, _s, _a)
      if key == "C" then if localSceneCb then localSceneCb(nil) end
      else
        local idx = tonumber(key)
        if idx then
          if localSceneCb then localSceneCb(isToWarehouse and ("wh_to_"..idx) or ("wh_from_"..idx)) end
        end
      end
    end,
  }
end

local function sceneWarehouseAmount(state, actions, localSceneCb, goodIdx, isToWarehouse)
  local goodName = GOOD_NAMES[goodIdx]
  local maxAmt   = isToWarehouse and (state.shipCargo[goodIdx] or 0)
                                  or (state.warehouseCargo[goodIdx] or 0)
  local direction = isToWarehouse and "to warehouse" or "from warehouse"
  local lines = {
    { text = string.format("Transfer %s %s (max %d, A=all):", goodName, direction, maxAmt), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=all): ",
    onType = function(text, _s, _a)
      local qty
      if text:upper() == "A" then qty = maxAmt
      else qty = tonumber(text) end
      if not qty or qty <= 0 then return "Enter a positive amount or A" end
      if qty > maxAmt then return string.format("Only %d available", maxAmt) end
      if isToWarehouse then actions.transferTo(goodIdx, math.floor(qty))
      else                  actions.transferFrom(goodIdx, math.floor(qty)) end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneWuAmount(state, actions, localSceneCb, isRepay)
  local maxAmt = isRepay
    and math.min(state.debt or 0, state.cash or 0)
    or  2 * (state.cash or 0)
  local verb = isRepay and "repay" or "borrow"
  local lines = {
    { text = string.format("Amount to %s (max %s, A=all):", verb, fmt(maxAmt)), color = AMBER },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=all): ",
    onType = function(text, _s, _a)
      local amt
      if text:upper() == "A" then amt = maxAmt
      else amt = tonumber(text) end
      if not amt or amt <= 0 then return "Enter a positive amount or A" end
      if amt > maxAmt then return string.format("Max is %s", fmt(maxAmt)) end
      if isRepay then actions.wuRepay(math.floor(amt))
      else            actions.wuBorrow(math.floor(amt)) end
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

local function sceneRepairAmount(state, actions, localSceneCb)
  local offer = state.shipOffer
  if not offer or not offer.repairRate then
    if localSceneCb then localSceneCb(nil) end
    return {}, nil
  end
  local maxCost = offer.repairRate * math.ceil(state.damage or 0) + 1
  local lines = {
    { text = string.format("Repair: %s/unit. Max cost to fully repair: %s",
        fmt(offer.repairRate), fmt(maxCost)), color = AMBER },
    { text = "Cash to spend (A=max):", color = GREEN },
  }
  return lines, {
    type = "type",
    typePlaceholder = "Amount (A=max): ",
    onType = function(text, _s, _a)
      local amt
      if text:upper() == "A" then amt = maxCost
      else amt = tonumber(text) end
      if not amt or amt <= 0 then return "Enter a positive amount or A" end
      actions.shipRepair(math.floor(amt))
      if localSceneCb then localSceneCb(nil) end
      return nil
    end,
  }
end

-- Main entry point
function PromptEngine.processState(state, localScene, actions, localSceneCb)
  -- Determine scene (priority order)
  if state.gameOver then
    return sceneGameOver(state, actions, localSceneCb)
  end
  if state.combat ~= nil then
    return sceneCombat(state, actions, localSceneCb)
  end
  if state.shipOffer ~= nil then
    if localScene == "repair" then
      return sceneRepairAmount(state, actions, localSceneCb)
    end
    return sceneShipOffers(state, actions, localSceneCb)
  end
  if state.currentPort == HONG_KONG and state.inWuSession then
    if localScene == "wu_repay" then return sceneWuAmount(state, actions, localSceneCb, true) end
    if localScene == "wu_borrow" then return sceneWuAmount(state, actions, localSceneCb, false) end
    return sceneWuSession(state, actions, localSceneCb)
  end
  -- Sub-scenes
  if localScene == "bank"        then return sceneBank(state, actions, localSceneCb) end
  if localScene == "bank_deposit"  then return sceneBankAmount(state, actions, localSceneCb, true) end
  if localScene == "bank_withdraw" then return sceneBankAmount(state, actions, localSceneCb, false) end
  if localScene == "warehouse"   then return sceneWarehouse(state, actions, localSceneCb) end
  if localScene == "wh_to"       then return sceneWarehouseGood(state, actions, localSceneCb, true) end
  if localScene == "wh_from"     then return sceneWarehouseGood(state, actions, localSceneCb, false) end
  if localScene and localScene:match("^wh_to_(%d)$") then
    local idx = tonumber(localScene:match("(%d)$"))
    return sceneWarehouseAmount(state, actions, localSceneCb, idx, true)
  end
  if localScene and localScene:match("^wh_from_(%d)$") then
    local idx = tonumber(localScene:match("(%d)$"))
    return sceneWarehouseAmount(state, actions, localSceneCb, idx, false)
  end
  if localScene == "buy"  then return sceneBuySell(state, actions, localSceneCb, true) end
  if localScene == "sell" then return sceneBuySell(state, actions, localSceneCb, false) end
  if localScene and localScene:match("^buy_good_(%d)$") then
    local idx = tonumber(localScene:match("(%d)$"))
    return sceneBuySellAmount(state, actions, localSceneCb, idx, true)
  end
  if localScene and localScene:match("^sell_good_(%d)$") then
    local idx = tonumber(localScene:match("(%d)$"))
    return sceneBuySellAmount(state, actions, localSceneCb, idx, false)
  end
  if localScene == "travel" then return sceneTravel(state, actions, localSceneCb) end
  if localScene == "settings" then return sceneSettings(state, actions, localSceneCb) end
  -- StartChoice: new game not yet started
  if (state.turnsElapsed or 1) == 1 and (state.destination or 0) == 0 then
    return sceneStartChoice(state, actions, localSceneCb)
  end
  -- Default: AtPort
  return sceneAtPort(state, actions, localSceneCb)
end

return PromptEngine
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui.Apple2.PromptEngine` (ModuleScript).

- [ ] **Step 2: Commit**

```bash
git add src/StarterGui/TaipanGui/Apple2/PromptEngine.lua
git commit -m "feat: add PromptEngine — all game scenes mapped to terminal output + promptDefs"
```

---

## Task 10: Create `Apple2Interface.lua`

**Files:**
- Create: `src/StarterGui/TaipanGui/Apple2Interface.lua`

- [ ] **Step 1: Write `Apple2Interface.lua`**

```lua
-- Apple2Interface.lua
-- Adapter: orchestrates Terminal, PromptEngine, KeyInput, GlitchLayer.
-- Implements { update(state), notify(message), destroy() }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Terminal     = require(script.Parent.Apple2.Terminal)
local GlitchLayer  = require(script.Parent.Apple2.GlitchLayer)
local KeyInput     = require(script.Parent.Apple2.KeyInput)
local PromptEngine = require(script.Parent.Apple2.PromptEngine)

local AMBER = Color3.fromRGB(200, 180, 80)
local RED   = Color3.fromRGB(220, 80, 80)

-- Server-driven scenes that override any localScene
local SERVER_SCENES = {
  gameOver   = function(s) return s.gameOver == true end,
  combat     = function(s) return s.combat ~= nil end,
  shipOffers = function(s) return s.shipOffer ~= nil end,
  wuSession  = function(s)
    local C = require(ReplicatedStorage.shared.Constants)
    return s.currentPort == C.HONG_KONG and s.inWuSession == true
  end,
}

local Apple2Interface = {}

function Apple2Interface.new(screenGui, actions)
  local term    = Terminal.new(5)         -- displayOrder 5
  local glitch  = GlitchLayer.new(term._gui)
  local ki      = KeyInput.new(screenGui)

  local lastState  = nil
  local localScene = nil  -- nil | "buy" | "sell" | "travel" | "warehouse" | "bank" |
                           --       "buy_good_N" | "sell_good_N" | "bank_deposit" |
                           --       "bank_withdraw" | "wu_repay" | "wu_borrow" |
                           --       "wh_to" | "wh_from" | "wh_to_N" | "wh_from_N" |
                           --       "settings" | "repair"

  local function isServerDriven(state)
    for _, check in pairs(SERVER_SCENES) do
      if check(state) then return true end
    end
    return false
  end

  local function render(state, scene)
    local lines, promptDef = PromptEngine.processState(state, scene, actions,
      function(newScene)
        -- Local scene transition callback: set scene, re-render without StateUpdate
        localScene = newScene
        render(lastState, localScene)
      end
    )

    term.clear()
    for _, line in ipairs(lines) do
      if type(line) == "table" then
        term.print(line.text, line.color)
      else
        term.print(line, nil)
      end
    end

    -- Attach terminal reference to promptDef for KeyInput type mode
    if promptDef then
      promptDef._terminal = term
      promptDef._onError  = function(errMsg)
        term.print(">> " .. errMsg, RED)
        ki.setPrompt(promptDef, state, actions)
      end
    end

    ki.setPrompt(promptDef, state, actions)
  end

  local adapter = {}

  function adapter.update(state)
    lastState = state

    -- Server-driven scenes clear localScene
    if isServerDriven(state) then
      localScene = nil
    end

    render(state, localScene)
  end

  function adapter.notify(message)
    -- Append notification below current display without clearing
    local parts = message:split("\n")
    for _, line in ipairs(parts) do
      term.print(line, AMBER)
    end
  end

  function adapter.destroy()
    ki.destroy()
    term.destroy()
    glitch.destroy()
  end

  return adapter
end

return Apple2Interface
```

Patch into Studio: `mcp__Roblox_Studio__script_write` with path `StarterGui.TaipanGui.Apple2Interface` (ModuleScript).

- [ ] **Step 2: Commit**

```bash
git add src/StarterGui/TaipanGui/Apple2Interface.lua
git commit -m "feat: add Apple2Interface adapter orchestrating Terminal/PromptEngine/KeyInput/GlitchLayer"
```

---

## Task 11: End-to-End Integration Test

No new files. This task verifies the complete system.

- [ ] **Step 1: Verify Apple II interface — basic flow**

In Studio, click **Play**. If you have a save with `uiMode = "modern"`:
- Stop Play
- Use the Studio Command Bar to call the `SetUIMode` Remote, or clear your DataStore save key to simulate new player
- Play again

With a new player or cleared save:
1. InterfacePicker appears → press A → Apple II interface appears
2. StartChoice scene: TAIPAN! title, press F for Firm
3. AtPort scene: Hong Kong, Jan 1860, prices visible, menu visible
4. Press B → BuySell good selector appears
5. Press 1 → Opium amount prompt appears
6. Type "10" + Enter → buy 10 Opium, screen re-renders
7. Press S → sell selector, press 1, type "5" + Enter → sell 5 Opium
8. Press T → travel selector, press 2 → travel to Shanghai
9. After travel: new port, new prices, full re-render
   Output panel: no errors throughout

- [ ] **Step 2: Verify Apple II interface — HK-only scenes**

Travel back to Hong Kong (port 1):
1. WuSession appears automatically (inWuSession = true on HK arrival)
2. Press P → amount prompt, type "100" + Enter → repay $100 debt
3. Press Q → leave Wu
4. AtPort at HK: Press K → Bank scene
5. Press D → deposit amount, type "50" + Enter → deposit $50
6. Press C → back to AtPort
7. Press W → Warehouse scene, transfer goods
8. ShipPanel appears if `shipOffer` is non-nil (HK arrival triggers it)

- [ ] **Step 3: Verify Apple II interface — Combat**

Sail between ports until a pirate encounter. Combat scene should appear with:
- BATTLE!! and SW% displayed
- Enemy grid as `[###......]`
- F/R/T options active on keyboard

Press F repeatedly to fight. After victory or running, normal port scene resumes.

- [ ] **Step 4: Verify interface switching**

In Apple II interface at port:
1. Press ! → settings sub-prompt: (M)odern (A)pple II (C)ancel
2. Press M → screen clears, modern panel UI appears
3. Settings button (⚙ UI) visible in PortPanel region
4. Click ⚙ UI → overlay appears → click Apple II → Apple II terminal returns
5. Output panel: no errors

- [ ] **Step 5: Verify returning player flow**

Stop Play (saves `uiMode`). Click Play again:
- If last mode was "modern": modern UI appears immediately, no picker
- If last mode was "apple2": Apple II interface appears immediately, no picker

- [ ] **Step 6: Commit**

```bash
git add .   # No new files, but capture any last-minute fixes
git commit -m "test: apple2 integration verified end-to-end"
```

---

## Task 12: Final Cleanup and Patch All Files to Studio

- [ ] **Step 1: Sync all files to Studio**

Use `mcp__Roblox_Studio__script_write` for each file that was edited on disk. Verify paths match. Run Studio **Play** once more to confirm clean state.

- [ ] **Step 2: Final commit**

```bash
git add -A
git commit -m "feat: complete Apple II interface implementation

- Dual-interface adapter architecture (ModernInterface / Apple2Interface)
- InterfacePicker for first-time selection (persisted via SetUIMode Remote)
- Terminal: 40-col bitmap font screen using TaipanStandardFont at TextSize=3
- PromptEngine: all 9 game scenes (AtPort, StartChoice, Combat, ShipOffers,
  WuSession, BuySell, Warehouse, Bank, GameOver, Settings)
- KeyInput: desktop keyboard + mobile virtual buttons via UserInputService.TouchEnabled
- GlitchLayer: stub overlay (ZIndex 100) for future CRT effects
- Live interface switching without rejoin
- Zero changes to existing panel files or engine modules"
```
