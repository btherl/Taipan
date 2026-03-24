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
  settingsBtn.Text = "UI"
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
