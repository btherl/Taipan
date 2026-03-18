-- init.client.lua  (LocalScript inside TaipanGui ScreenGui)
-- GameController: wires all UI panels to server RemoteEvents.
-- Receives state snapshots from server and distributes to panels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

-- Sanity check: Panels folder must exist as a child of this LocalScript's container
assert(script:FindFirstChild("Panels"),
  "TaipanGui: 'Panels' folder missing — check Studio structure")

local Remotes          = require(ReplicatedStorage.Remotes)
local StatusStrip      = require(script.Panels.StatusStrip)
local InventoryPanel   = require(script.Panels.InventoryPanel)
local PricesPanel      = require(script.Panels.PricesPanel)
local BuySellPanel     = require(script.Panels.BuySellPanel)
local PortPanel        = require(script.Panels.PortPanel)
local WarehousePanel   = require(script.Panels.WarehousePanel)
local WuPanel          = require(script.Panels.WuPanel)
local BankPanel        = require(script.Panels.BankPanel)
local MessagePanel     = require(script.Panels.MessagePanel)
local GameOverPanel    = require(script.Panels.GameOverPanel)
local CombatPanel      = require(script.Panels.CombatPanel)
local ShipPanel        = require(script.Panels.ShipPanel)
local StartPanel       = require(script.Panels.StartPanel)

-- Build the ScreenGui root frame
local screenGui = script.Parent  -- TaipanGui is already a ScreenGui in StarterGui
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.new(0, 480, 1, 0)
root.Position = UDim2.new(0, 0, 0, 0)
root.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
root.BorderSizePixel = 0
root.Parent = screenGui

-- Instantiate panels
local portPanel      = PortPanel.new(root,
  function(dest) Remotes.TravelTo:FireServer(dest) end,
  function() Remotes.Retire:FireServer() end,
  function() Remotes.QuitGame:FireServer() end
)
local statusStrip    = StatusStrip.new(root)
local inventoryPanel = InventoryPanel.new(root)
local pricesPanel    = PricesPanel.new(root)
local buySellPanel   = BuySellPanel.new(
  root,
  function(goodIndex, qty) Remotes.BuyGoods:FireServer(goodIndex, qty) end,
  function(goodIndex, qty) Remotes.SellGoods:FireServer(goodIndex, qty) end,
  function() Remotes.EndTurn:FireServer() end
)
local warehousePanel = WarehousePanel.new(
  root,
  function(goodIndex, qty) Remotes.TransferToWarehouse:FireServer(goodIndex, qty) end,
  function(goodIndex, qty) Remotes.TransferFromWarehouse:FireServer(goodIndex, qty) end
)
local messagePanel = MessagePanel.new(root)
local wuPanel = WuPanel.new(
  root,
  function(amount) Remotes.WuRepay:FireServer(amount) end,
  function(amount) Remotes.WuBorrow:FireServer(amount) end,
  function() Remotes.LeaveWu:FireServer() end,
  function() Remotes.BuyLiYuenProtection:FireServer() end
)
local bankPanel = BankPanel.new(
  root,
  function(amount) Remotes.BankDeposit:FireServer(amount) end,
  function(amount) Remotes.BankWithdraw:FireServer(amount) end
)
local gameOverPanel = GameOverPanel.new(root, function()
  Remotes.RestartGame:FireServer()
end)
local combatPanel = CombatPanel.new(root,
  function() Remotes.CombatFight:FireServer() end,
  function() Remotes.CombatRun:FireServer() end,
  function(goodIndex, qty) Remotes.CombatThrow:FireServer(goodIndex, qty) end
)
local shipPanel = ShipPanel.new(root,
  function(amount) Remotes.ShipRepair:FireServer(amount) end,
  function() Remotes.AcceptUpgrade:FireServer() end,
  function() Remotes.DeclineUpgrade:FireServer() end,
  function() Remotes.AcceptGun:FireServer() end,
  function() Remotes.DeclineGun:FireServer() end,
  function() Remotes.ShipPanelDone:FireServer() end
)

-- Start-choice overlay: shown until player picks firm or ship
local startPanel = StartPanel.new(root, function(startChoice)
  Remotes.ChooseStart:FireServer(startChoice)
  Remotes.RequestStateUpdate:FireServer()
end)

-- Receive state updates from server and refresh all panels
Remotes.StateUpdate.OnClientEvent:Connect(function(state)
  startPanel.hide()
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
end)

-- Server notifications (Wu, Li Yuen, etc.)
Remotes.Notify.OnClientEvent:Connect(function(message)
  messagePanel.show(message)
end)

